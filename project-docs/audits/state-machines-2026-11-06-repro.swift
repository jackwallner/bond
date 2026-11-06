// State machine audit repro suite, 2026-11-06. Not part of the build.
// To run: append the suite below to an existing file in BondTests (a new file needs
// `xcodegen generate`), then
//   gh-sim test --scheme Bond --only BondTests/StateMachineAuditRepro
// Recorded run: bond@20261106-142641-5308-claude-imac4a60-1106-152539-5344
// (6 failing claims, 6 passing controls).
// Note: sm4 and sm1 call repo.refresh()/loadCouple() whose partner-profile request goes
// to the configured backend; it returns no row, which is the failure sm4 needs.

import Foundation
import Testing

@testable import Bond

// MARK: - StateMachineAuditRepro (temporary, 2026-11-06 audit)

@MainActor
@Suite(.serialized)
struct StateMachineAuditRepro {
    private let me = UUID()
    private let partner = UUID()
    private let coupleId = UUID()

    private func reminder(
        title: String, author: UUID, target: UUID, type: String = "one_time",
        fireAt: Date, rrule: String? = nil, createdAt: Date? = nil
    ) -> ReminderDTO {
        ReminderDTO(
            id: UUID(), coupleId: coupleId, authorId: author, targetId: target,
            title: title, body: nil, loveLanguage: .words, triggerType: type,
            fireAt: fireAt, rrule: rrule, geofence: nil, windowStart: nil, windowEnd: nil,
            status: "scheduled", surpriseHiddenFromPartner: false, createdAt: createdAt
        )
    }

    private func repoAndPairing() -> (ReminderRepository, PairingService) {
        let pairing = PairingService()
        pairing.coupleId = coupleId
        return (ReminderRepository(pairing: pairing), pairing)
    }

    // MARK: SM-1 Insights count the partner's own reminders

    private func insightsFixture() -> (mine: ReminderDTO, theirs: ReminderDTO) {
        let tenDaysAgo = Date.now.addingTimeInterval(-10 * 86_400)
        let soon = Date.now.addingTimeInterval(86_400)
        let later = Date.now.addingTimeInterval(5 * 86_400)
        return (
            reminder(title: "Mine", author: me, target: me, type: "recurring",
                     fireAt: later, rrule: "FREQ=DAILY", createdAt: tenDaysAgo),
            reminder(title: "Partner private", author: partner, target: partner, type: "recurring",
                     fireAt: soon, rrule: "FREQ=DAILY", createdAt: tenDaysAgo)
        )
    }

    @Test func sm1_control_insightsOverMyOwnRemindersCountOne() {
        let (mine, _) = insightsFixture()
        let analyzer = LoveLanguageAnalyzer(reminders: [mine], events: [])
        #expect(analyzer.reminderCounts().map(\.1).reduce(0, +) == 1)
        #expect(analyzer.followThrough().map(\.reminder.title) == ["Mine"])
    }

    @Test func sm1_insightsOnlyCountAndNameWhatTheUserCanSee() async {
        let (mine, theirs) = insightsFixture()
        // Precondition 1: the widget documents what this app shows a user and drops the
        // partner's own reminder (it fires sooner, so it would win if it were kept).
        let widget = WidgetSnapshot.make(reminders: [mine, theirs], milestones: [], userId: me)
        #expect(widget.nextReminder?.title == "Mine")
        // Precondition 2: the repository hands the client both rows (RLS lets the couple read them).
        let (repo, _) = repoAndPairing()
        repo.loadRows = { _ in [mine, theirs] }
        await repo.refresh()
        #expect(repo.reminders.count == 2)
        // StatsView.analyzer is exactly this (StatsView.swift:11-13).
        let analyzer = LoveLanguageAnalyzer(reminders: repo.reminders, events: [])
        #expect(analyzer.reminderCounts().map(\.1).reduce(0, +) == 1, "Total reminders counts the partner's private one")
        #expect(analyzer.followThrough().map(\.reminder.title) == ["Mine"], "Follow-through names the partner's private reminder")
    }

    // MARK: SM-2 A save whose re-read failed arms the old time

    @Test func sm2_control_rescheduleThenSuccessfulRefreshArmsTheNewTime() async throws {
        let old = reminder(title: "Flowers", author: partner, target: me, fireAt: .now.addingTimeInterval(2 * 3_600))
        var moved = old
        moved.fireAt = .now.addingTimeInterval(6 * 3_600)
        let (repo, _) = repoAndPairing()
        repo.currentUserId = { [me] in me }
        repo.rescheduleRow = { _ in }
        var armed: [[ReminderDTO]] = []
        repo.scheduleNotifications = { _, rs, _, _ in armed.append(rs) }
        repo.loadRows = { _ in [old] }
        await repo.refresh()
        repo.loadRows = { _ in [moved] }
        try await repo.upsert(moved)
        await repo.rescheduleNotifications(forSelfUserId: me, events: [])
        #expect(armed.count == 1)
        #expect(armed.first?.first?.fireAt == moved.fireAt)
    }

    @Test func sm2_savedTimeIsWhatGetsArmedEvenWhenTheReReadFails() async throws {
        let old = reminder(title: "Flowers", author: partner, target: me, fireAt: .now.addingTimeInterval(2 * 3_600))
        var moved = old
        moved.fireAt = .now.addingTimeInterval(6 * 3_600)
        let (repo, _) = repoAndPairing()
        repo.currentUserId = { [me] in me }
        var serverAccepted = 0
        repo.rescheduleRow = { _ in serverAccepted += 1 }
        var armed: [[ReminderDTO]] = []
        repo.scheduleNotifications = { _, rs, _, _ in armed.append(rs) }
        repo.loadRows = { _ in [old] }
        await repo.refresh()
        #expect(repo.hasLoaded)
        repo.loadRows = { _ in throw URLError(.networkConnectionLost) }
        try await repo.upsert(moved)                    // the editor's save: no throw, so it dismisses
        #expect(serverAccepted == 1)
        await repo.rescheduleNotifications(forSelfUserId: me, events: [])   // the editor's next line
        #expect(armed.count == 1)
        #expect(armed.first?.first?.fireAt == moved.fireAt, "armed from the pre-save list")
    }

    // MARK: SM-3 Weekly "done" window: client week vs the server's Monday week

    private func usCalendar(firstWeekday: Int) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        cal.firstWeekday = firstWeekday
        cal.minimumDaysInFirstWeek = 1
        return cal
    }

    private func pacific(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = h
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return cal.date(from: c)!
    }

    @Test func sm3_control_aMondayFirstCalendarMatchesTheServersWeek() {
        let cal = usCalendar(firstWeekday: 2)
        let weekly = reminder(title: "Date night", author: partner, target: me, type: "recurring",
                              fireAt: pacific(2026, 11, 1, 9), rrule: "FREQ=WEEKLY")
        let sunday = pacific(2026, 11, 8, 10)
        #expect(cal.component(.weekday, from: sunday) == 1)
        #expect(weekly.currentPeriodStart(at: sunday, calendar: cal) == pacific(2026, 11, 2))
    }

    @Test func sm3_aWeeklyReminderIsDoneForTheSameWeekOnDeviceAndServer() {
        // 0014 reminder_done_now: date_trunc('week', ...) starts the week on Monday.
        let serverWeekStart = pacific(2026, 11, 2)
        let cal = usCalendar(firstWeekday: 1)                   // en_US
        let weekly = reminder(title: "Date night", author: partner, target: me, type: "recurring",
                              fireAt: pacific(2026, 11, 1, 9), rrule: "FREQ=WEEKLY")
        let sunday = pacific(2026, 11, 8, 10)
        #expect(cal.firstWeekday == 1)
        #expect(cal.component(.weekday, from: sunday) == 1)
        #expect(weekly.currentPeriodStart(at: sunday, calendar: cal) == serverWeekStart,
                "device starts a new week on Sunday, the server does not")
    }

    // MARK: SM-4 A half-failed couple lookup leaves half the state

    @Test func sm4_control_aFailedCouplesRequestChangesNothing() async {
        let service = SupabaseService.shared
        let before = service.currentUserId
        service.currentUserId = me
        defer { service.currentUserId = before }
        let old = UUID()
        let pairing = PairingService()
        pairing.coupleId = old
        pairing.solo = true
        var told = 0
        pairing.onRelationshipChange = { told += 1 }
        pairing.fetchCouples = { _ in throw URLError(.notConnectedToInternet) }
        await pairing.loadCouple()
        #expect(pairing.lastLoadFailed)
        #expect(pairing.coupleId == old && pairing.solo && told == 0)
    }

    @Test func sm4_aLookupThatFailsKeepsWhatWasKnown() async {
        let service = SupabaseService.shared
        let before = service.currentUserId
        service.currentUserId = me
        defer { service.currentUserId = before }
        let old = UUID()
        let newCouple = UUID()
        let mine = me, theirs = partner
        let pairing = PairingService()
        pairing.coupleId = old
        pairing.solo = true
        var told = 0
        pairing.onRelationshipChange = { told += 1 }
        // The couples request works; the partner-profile request that follows cannot.
        pairing.fetchCouples = { _ in
            [CoupleDTO(id: newCouple, partnerA: mine, partnerB: theirs, pairedAt: nil, solo: false)]
        }
        await pairing.loadCouple()
        #expect(pairing.lastLoadFailed, "precondition: the profile request failed")
        let unchanged = pairing.coupleId == old && pairing.solo
        #expect(unchanged || pairing.partnerProfile != nil,
                "paired with no partner profile: coupleId=\(String(describing: pairing.coupleId)) solo=\(pairing.solo)")
        #expect(told == 0, "a failed lookup announced a relationship change")
    }

    // MARK: SM-5 A launch whose completions failed to load rebuilds as if nothing was done

    @Test func sm5_control_aFailedReminderFetchLeavesTheScheduleAlone() async {
        let (repo, _) = repoAndPairing()
        var rebuilds = 0
        repo.scheduleNotifications = { _, _, _, _ in rebuilds += 1 }
        repo.loadRows = { _ in throw URLError(.timedOut) }
        await repo.refresh()
        await repo.rescheduleNotifications(forSelfUserId: me, events: [], requestAuthIfNeeded: false)
        #expect(!repo.hasLoaded)
        #expect(rebuilds == 0)
    }

    @Test func sm5_aLaunchWithoutCompletionsLeavesTheScheduleAlone() async {
        let handled = reminder(title: "Call her", author: me, target: me, fireAt: .now.addingTimeInterval(4 * 3_600))
        let (repo, _) = repoAndPairing()
        var rebuilt: [[ReminderEventDTO]] = []
        repo.scheduleNotifications = { _, _, events, _ in rebuilt.append(events) }
        repo.loadRows = { _ in [handled] }
        // ReminderEventRepository has no stub seam. Its failure path (catch at
        // ReminderEventRepository.swift:34-37) leaves `events` at its initial [], and
        // so does a repository with no couple, which returns at the guard: that is
        // the stand-in used here. Cold launch, as ReminderListView.task runs it (:114-126).
        let eventsRepo = ReminderEventRepository(pairing: PairingService())
        await repo.refresh()
        await eventsRepo.refresh()
        #expect(repo.hasLoaded, "precondition: the reminders loaded")
        #expect(eventsRepo.events.isEmpty, "precondition: no completions are known")
        await repo.rescheduleNotifications(
            forSelfUserId: me, events: eventsRepo.events, requestAuthIfNeeded: false
        )
        #expect(rebuilt.isEmpty, "rebuilt every pending notification from completions=\(rebuilt.first?.count ?? -1)")
    }

    // MARK: SM-6 Undo removes one completion, a second one keeps it done

    private func completion(_ reminder: ReminderDTO, at when: Date) -> ReminderEventDTO {
        ReminderEventDTO(
            id: UUID(), reminderId: reminder.id, coupleId: coupleId,
            firedAt: when, actedAt: when, reaction: nil
        )
    }

    @Test func sm6_control_undoOfASingleCompletionReopensTheReminder() {
        let r = reminder(title: "Flowers", author: me, target: me, fireAt: .now.addingTimeInterval(3_600))
        var events = [completion(r, at: .now)]
        #expect(r.isCompleted(in: events))
        let undone = r.currentCompletionEvent(in: events)
        events.removeAll { $0.id == undone?.id }      // ReminderEventRepository.deleteEvent
        #expect(!r.isCompleted(in: events))
    }

    @Test func sm6_undoReopensTheReminderEvenWhenTwoCompletionsWereRecorded() {
        // Two completions for one reminder: both partners see it, and the events list is
        // not on the realtime feed, so the second tap sees a stale "not done".
        let r = reminder(title: "Flowers", author: partner, target: me, fireAt: .now.addingTimeInterval(3_600))
        var events = [completion(r, at: .now.addingTimeInterval(-60)), completion(r, at: .now)]
        #expect(r.isCompleted(in: events))
        let undone = r.currentCompletionEvent(in: events)
        events.removeAll { $0.id == undone?.id }
        #expect(!r.isCompleted(in: events), "Not done left \(events.count) completion(s) in place")
    }
}
