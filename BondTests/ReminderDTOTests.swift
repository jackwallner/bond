import Foundation
import Testing

@testable import Bond

struct ReminderDTOTests {
    private let coupleId = UUID()
    private let authorId = UUID()
    private let targetId = UUID()

    @Test func trigger_oneTime() {
        let r = makeReminder(triggerType: "one_time", fireAt: .now)
        #expect(r.trigger == .oneTime(fireAt: r.fireAt!))
    }

    @Test func trigger_recurring() {
        let r = makeReminder(triggerType: "recurring", fireAt: .now, rrule: "FREQ=WEEKLY")
        #expect(r.trigger == .recurring(rrule: "FREQ=WEEKLY", nextFire: r.fireAt!))
    }

    @Test func trigger_location() {
        let g = Geofence(latitude: 0, longitude: 0, radiusMeters: 200, label: "Home")
        let r = makeReminder(triggerType: "location", geofence: g)
        #expect(r.trigger == .location(geofence: g, onEntry: true))
    }

    @Test func trigger_randomWindow() {
        let s = Date.now
        let e = s.addingTimeInterval(3600)
        let r = makeReminder(triggerType: "random_window", windowStart: s, windowEnd: e)
        #expect(r.trigger == .randomWindow(start: s, end: e))
    }

    @Test func trigger_unknownType_returnsNil() {
        let r = makeReminder(triggerType: "unknown")
        #expect(r.trigger == nil)
    }

    @Test func trigger_missingFields_returnsNil() {
        let r = makeReminder(triggerType: "one_time", fireAt: nil)
        #expect(r.trigger == nil)
    }

    // MARK: - Codable

    @Test func codable_roundTrip() throws {
        let r = makeReminder(triggerType: "recurring", fireAt: .now, rrule: "FREQ=DAILY")
        let data = try JSONEncoder().encode(r)
        let decoded = try JSONDecoder().decode(ReminderDTO.self, from: data)
        #expect(decoded == r)
        #expect(decoded.trigger?.kindRaw == "recurring")
    }

    // MARK: - Encoding

    // An upsert only changes the columns that are in its body. A field the user
    // cleared (the note, a repeat rule) has to go out as an explicit null, or the
    // server keeps the old value and the edit is silently lost on the next refresh.

    @Test func encode_sendsClearedFieldsAsExplicitNulls() throws {
        let r = makeReminder(triggerType: "one_time")
        let json = try encodedObject(r)
        for key in ["body", "fire_at", "rrule", "geofence", "window_start", "window_end"] {
            #expect(json[key] is NSNull, "\(key) must go out as null")
        }
    }

    @Test func encode_keepsTheValuesItIsGiven() throws {
        var r = makeReminder(triggerType: "recurring", fireAt: .now, rrule: "FREQ=WEEKLY")
        r.body = "Her favourite place"
        let json = try encodedObject(r)
        #expect(json["rrule"] as? String == "FREQ=WEEKLY")
        #expect(json["body"] as? String == "Her favourite place")
        #expect(json["fire_at"] != nil)
        #expect(!(json["fire_at"] is NSNull))
    }

    @Test func encode_leavesCreatedAtToTheDatabaseWhenItIsUnknown() throws {
        let r = makeReminder(triggerType: "one_time", fireAt: .now)
        let json = try encodedObject(r)
        #expect(json["created_at"] == nil)
    }

    @Test func clearedNote_roundTripsAsAClearedNote() throws {
        var r = makeReminder(triggerType: "one_time", fireAt: .now)
        r.body = nil
        let decoded = try JSONDecoder().decode(ReminderDTO.self, from: JSONEncoder().encode(r))
        #expect(decoded.body == nil)
        #expect(decoded == r)
    }

    private func encodedObject(_ reminder: ReminderDTO) throws -> [String: Any] {
        let data = try JSONEncoder().encode(reminder)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Helpers

    private func makeReminder(
        triggerType: String,
        fireAt: Date? = nil,
        rrule: String? = nil,
        geofence: Geofence? = nil,
        windowStart: Date? = nil,
        windowEnd: Date? = nil
    ) -> ReminderDTO {
        ReminderDTO(
            id: UUID(),
            coupleId: coupleId,
            authorId: authorId,
            targetId: targetId,
            title: "Test reminder",
            body: nil,
            loveLanguage: .words,
            triggerType: triggerType,
            fireAt: fireAt,
            rrule: rrule,
            geofence: geofence,
            windowStart: windowStart,
            windowEnd: windowEnd,
            status: "scheduled",
            surpriseHiddenFromPartner: false,
            createdAt: nil
        )
    }
}


/// Launch behaviour of the on-device schedule. Every launch rebuilds the
/// pending notifications from the repository's list, so the list has to be
/// the server's, not the empty starting value of a launch whose fetch failed.
/// The scheduler is replaced by a recorder: a test host has no notification
/// permission, so real requests cannot be added or read back there.
@MainActor
struct LaunchRescheduleTests {
    private let me = UUID()
    private let coupleId = UUID()

    private func repositoryAndPairing() -> (repo: ReminderRepository, pairing: PairingService) {
        let pairing = PairingService()
        pairing.coupleId = coupleId
        return (ReminderRepository(pairing: pairing), pairing)
    }

    private func reminderForMe(in hours: Double) -> ReminderDTO {
        ReminderDTO(
            id: UUID(),
            coupleId: coupleId,
            authorId: me,
            targetId: me,
            title: "Call her at lunch",
            body: nil,
            loveLanguage: .words,
            triggerType: "one_time",
            fireAt: Date.now.addingTimeInterval(hours * 3_600),
            rrule: nil,
            geofence: nil,
            windowStart: nil,
            windowEnd: nil,
            status: "scheduled",
            surpriseHiddenFromPartner: false,
            createdAt: nil
        )
    }

    @Test func failedLaunchFetch_doesNotRebuildTheSchedule() async {
        let (repo, _) = repositoryAndPairing()
        var rebuilds: [[ReminderDTO]] = []
        repo.scheduleNotifications = { _, reminders, _, _ in rebuilds.append(reminders) }
        repo.loadRows = { _ in throw URLError(.notConnectedToInternet) }

        await repo.refresh()
        await repo.rescheduleNotifications(forSelfUserId: me, events: [], requestAuthIfNeeded: false)

        #expect(repo.hasLoaded == false)
        #expect(rebuilds.isEmpty)
    }

    @Test func successfulFetch_rebuildsTheScheduleFromTheFetchedList() async {
        let reminder = reminderForMe(in: 2)
        let (repo, _) = repositoryAndPairing()
        var rebuilds: [[ReminderDTO]] = []
        repo.scheduleNotifications = { _, reminders, _, _ in rebuilds.append(reminders) }
        repo.loadRows = { _ in [reminder] }

        await repo.refresh()
        await repo.rescheduleNotifications(forSelfUserId: me, events: [], requestAuthIfNeeded: false)

        #expect(repo.hasLoaded)
        #expect(rebuilds == [[reminder]])
    }

    @Test func loadedList_doesNotCarryOverToAnotherCouple() async {
        let (repo, pairing) = repositoryAndPairing()
        var rebuilds: [[ReminderDTO]] = []
        repo.scheduleNotifications = { _, reminders, _, _ in rebuilds.append(reminders) }
        repo.loadRows = { _ in [] }
        await repo.refresh()
        #expect(repo.hasLoaded)

        // Sign out, then sign in as someone else: the old list says nothing about the new couple.
        pairing.coupleId = UUID()
        await repo.rescheduleNotifications(forSelfUserId: me, events: [], requestAuthIfNeeded: false)

        #expect(repo.hasLoaded == false)
        #expect(rebuilds.isEmpty)
    }

    @Test func loadedEmptyList_stillRebuilds_soDeletedRemindersStopFiring() async {
        let (repo, _) = repositoryAndPairing()
        var rebuilds: [[ReminderDTO]] = []
        repo.scheduleNotifications = { _, reminders, _, _ in rebuilds.append(reminders) }
        repo.loadRows = { _ in [] }

        await repo.refresh()
        await repo.rescheduleNotifications(forSelfUserId: me, events: [], requestAuthIfNeeded: false)

        #expect(repo.hasLoaded)
        #expect(rebuilds == [[]])
    }

    @Test func importedPack_isArmedWithoutWaitingForTheNextLaunch() async throws {
        let pack = [reminderForMe(in: 24), reminderForMe(in: 48)]
        let (repo, _) = repositoryAndPairing()
        var rebuilds: [[ReminderDTO]] = []
        repo.insertRows = { _ in }
        repo.loadRows = { _ in pack }
        repo.scheduleNotifications = { _, reminders, _, _ in rebuilds.append(reminders) }

        try await repo.importReminders(pack, forSelfUserId: me, events: [])

        #expect(repo.reminders == pack)
        #expect(rebuilds == [pack])
    }

    @Test func importThatFailsToSave_leavesTheScheduleAlone() async {
        let pack = [reminderForMe(in: 24)]
        let (repo, _) = repositoryAndPairing()
        var rebuilds: [[ReminderDTO]] = []
        repo.insertRows = { _ in throw URLError(.notConnectedToInternet) }
        repo.scheduleNotifications = { _, reminders, _, _ in rebuilds.append(reminders) }

        await #expect(throws: URLError.self) {
            try await repo.importReminders(pack, forSelfUserId: me, events: [])
        }

        #expect(rebuilds.isEmpty)
    }

    @Test func returningToTheForeground_picksUpWhatThePartnerAddedAndArmsIt() async {
        let before = reminderForMe(in: 5)
        let added = reminderForMe(in: 3)
        let (repo, _) = repositoryAndPairing()
        var served = [before]
        var rebuilds: [[ReminderDTO]] = []
        repo.loadRows = { _ in served }
        repo.scheduleNotifications = { _, reminders, _, _ in rebuilds.append(reminders) }
        await repo.refresh()

        // The realtime feed is not replayed after the app was suspended, so the
        // partner's new reminder is only on the server.
        served = [before, added]
        await repo.catchUp(forSelfUserId: me, refreshEvents: { [] })

        #expect(repo.reminders == [before, added])
        #expect(rebuilds == [[before, added]])
    }

    @Test func catchUp_usesTheEventsItJustFetched_andNeverAsksForPermission() async {
        let done = ReminderEventDTO(
            id: UUID(), reminderId: UUID(), coupleId: coupleId, firedAt: .now, actedAt: .now, reaction: nil
        )
        let (repo, _) = repositoryAndPairing()
        var seen: [(Int, Bool)] = []
        repo.loadRows = { _ in [] }
        repo.scheduleNotifications = { _, _, events, mayAsk in seen.append((events.count, mayAsk)) }

        await repo.catchUp(forSelfUserId: me, refreshEvents: { [done] })

        #expect(seen.map(\.0) == [1])
        #expect(seen.map(\.1) == [false])
    }

    @Test func catchUpBeforeAnythingLoaded_andOffline_doesNotTouchTheSchedule() async {
        let (repo, _) = repositoryAndPairing()
        var rebuilds: [[ReminderDTO]] = []
        repo.loadRows = { _ in throw URLError(.notConnectedToInternet) }
        repo.scheduleNotifications = { _, reminders, _, _ in rebuilds.append(reminders) }

        await repo.catchUp(forSelfUserId: me, refreshEvents: { [] })

        #expect(rebuilds.isEmpty)
    }

    @Test func liveChangeFromThePartner_isArmedWithoutWaitingForTheNextForeground() async {
        let before = reminderForMe(in: 5)
        let added = reminderForMe(in: 3)
        let (repo, _) = repositoryAndPairing()
        var served = [before]
        var rebuilds: [[ReminderDTO]] = []
        let userId = me
        repo.loadRows = { _ in served }
        repo.scheduleNotifications = { _, reminders, _, _ in rebuilds.append(reminders) }
        repo.armingContext = { (userId, []) }
        await repo.refresh()

        // The partner adds a reminder while this app is open: the realtime feed
        // delivers it, and the phone locking afterwards is not a return to the
        // foreground, so nothing else would arm it before it is due.
        served = [before, added]
        await repo.handleRemoteChange()

        #expect(repo.reminders == [before, added])
        #expect(rebuilds == [[before, added]])
    }

    @Test func liveChange_beforeAnyListLoaded_andOffline_doesNotTouchTheSchedule() async {
        let (repo, _) = repositoryAndPairing()
        var rebuilds: [[ReminderDTO]] = []
        let userId = me
        repo.loadRows = { _ in throw URLError(.notConnectedToInternet) }
        repo.scheduleNotifications = { _, reminders, _, _ in rebuilds.append(reminders) }
        repo.armingContext = { (userId, []) }

        await repo.handleRemoteChange()

        #expect(rebuilds.isEmpty)
    }

    @Test func rearm_hasNobodyToArmFor_withoutAContext() async {
        let (repo, _) = repositoryAndPairing()
        var rebuilds = 0
        repo.loadRows = { _ in [] }
        repo.scheduleNotifications = { _, _, _, _ in rebuilds += 1 }
        await repo.refresh()

        await repo.rearm()

        #expect(rebuilds == 0)
    }

    @Test func rearm_usesTheContextsUserAndEvents_andNeverAsksForPermission() async {
        let done = ReminderEventDTO(
            id: UUID(), reminderId: UUID(), coupleId: coupleId, firedAt: .now, actedAt: .now, reaction: nil
        )
        let (repo, _) = repositoryAndPairing()
        var seen: [(UUID, Int, Bool)] = []
        let userId = me
        repo.loadRows = { _ in [] }
        repo.scheduleNotifications = { user, _, events, mayAsk in seen.append((user, events.count, mayAsk)) }
        repo.armingContext = { (userId, [done]) }
        await repo.refresh()

        await repo.rearm()

        #expect(seen.map(\.0) == [me])
        #expect(seen.map(\.1) == [1])
        #expect(seen.map(\.2) == [false])
    }

    @Test func rebuild_forwardsTheUserTheEventsAndTheTrigger() async {
        let reminder = reminderForMe(in: 3)
        let event = ReminderEventDTO(
            id: UUID(), reminderId: reminder.id, coupleId: coupleId,
            firedAt: .now, actedAt: .now, reaction: nil
        )
        let (repo, _) = repositoryAndPairing()
        var seen: [(UUID, Int, Bool)] = []
        repo.scheduleNotifications = { user, _, events, mayAsk in seen.append((user, events.count, mayAsk)) }
        repo.loadRows = { _ in [reminder] }
        await repo.refresh()

        await repo.rescheduleNotifications(forSelfUserId: me, events: [event], requestAuthIfNeeded: false)
        await repo.rescheduleNotifications(forSelfUserId: me, events: [])

        #expect(seen.map(\.0) == [me, me])
        #expect(seen.map(\.1) == [1, 0])
        #expect(seen.map(\.2) == [false, true])
    }
}

// MARK: - State machine audit 2026-11-06: completions and saves (B2, B8, B12, B14)

/// Regression tests moved from project-docs/audits/state-machines-2026-11-06-repro.swift
/// (sm2, sm5, sm6) plus the review's B12.
@MainActor
@Suite(.serialized)
struct CompletionStateTests {
    private let me = UUID()
    private let partner = UUID()
    private let coupleId = UUID()

    private func reminder(
        title: String, author: UUID, target: UUID, type: String = "one_time",
        fireAt: Date, rrule: String? = nil
    ) -> ReminderDTO {
        ReminderDTO(
            id: UUID(), coupleId: coupleId, authorId: author, targetId: target,
            title: title, body: nil, loveLanguage: .words, triggerType: type,
            fireAt: fireAt, rrule: rrule, geofence: nil, windowStart: nil, windowEnd: nil,
            status: "scheduled", surpriseHiddenFromPartner: false, createdAt: nil
        )
    }

    private func completion(_ reminder: ReminderDTO, at when: Date) -> ReminderEventDTO {
        ReminderEventDTO(
            id: UUID(), reminderId: reminder.id, coupleId: coupleId,
            firedAt: when, actedAt: when, reaction: nil
        )
    }

    private func repos() -> (ReminderRepository, ReminderEventRepository, PairingService) {
        let pairing = PairingService()
        pairing.coupleId = coupleId
        return (ReminderRepository(pairing: pairing), ReminderEventRepository(pairing: pairing), pairing)
    }

    /// What a rebuild would arm on this phone, as `NotificationScheduler.reschedule` decides it.
    private func armed(_ reminders: [ReminderDTO], _ events: [ReminderEventDTO]) -> [String] {
        reminders
            .filter { NotificationScheduler.armsLocally($0, me: me, serverDelivers: false) }
            .filter { !($0.isCompleted(in: events) && !$0.repeatsOnSchedule) }
            .map(\.title)
    }

    // B2 (sm5): a launch whose completions failed to load must not re-arm a handled one-shot.

    @Test func b2_aLaunchWhoseCompletionsFailedDoesNotPingAHandledReminderAgain() async {
        let handled = reminder(title: "Call her", author: me, target: me, fireAt: .now.addingTimeInterval(4 * 3_600))
        let (repo, eventsRepo, _) = repos()
        var armedTitles: [[String]] = []
        repo.scheduleNotifications = { _, reminders, events, _ in armedTitles.append(armed(reminders, events)) }
        repo.loadRows = { [handled] _ in [handled] }
        eventsRepo.loadRows = { _ in throw URLError(.timedOut) }

        // Cold launch, as ReminderListView.task runs it.
        await repo.refresh()
        await eventsRepo.refresh()
        #expect(repo.hasLoaded, "precondition: the reminders loaded")
        #expect(!eventsRepo.hasLoaded, "precondition: the completions did not")
        await repo.rescheduleNotifications(forSelfUserId: me, events: eventsRepo.loadedEvents, requestAuthIfNeeded: false)

        #expect(!armedTitles.contains { $0.contains("Call her") }, "re-armed a handled reminder: \(armedTitles)")
    }

    @Test func b2_control_loadedCompletionsKeepTheHandledReminderQuiet_andArmTheRest() async {
        let handled = reminder(title: "Call her", author: me, target: me, fireAt: .now.addingTimeInterval(4 * 3_600))
        let open = reminder(title: "Flowers", author: me, target: me, fireAt: .now.addingTimeInterval(5 * 3_600))
        let done = completion(handled, at: .now)
        let (repo, eventsRepo, _) = repos()
        var armedTitles: [[String]] = []
        repo.scheduleNotifications = { _, reminders, events, _ in armedTitles.append(armed(reminders, events)) }
        repo.loadRows = { [handled, open] _ in [handled, open] }
        eventsRepo.loadRows = { [done] _ in [done] }

        await repo.catchUp(forSelfUserId: me) {
            await eventsRepo.refresh()
            return eventsRepo.loadedEvents
        }

        #expect(armedTitles == [["Flowers"]])
    }

    @Test func b2_completionsOfAnotherCoupleAreNotTrusted() async {
        let (_, eventsRepo, pairing) = repos()
        eventsRepo.loadRows = { _ in [] }
        await eventsRepo.refresh()
        #expect(eventsRepo.loadedEvents == [])
        pairing.coupleId = UUID()
        #expect(eventsRepo.loadedEvents == nil)
    }

    // B14 (sm2): the saved time is what gets armed even when the re-read after the save fails.

    @Test func b14_aRescheduleWhoseReReadFailedArmsTheNewTime() async throws {
        let old = reminder(title: "Flowers", author: partner, target: me, fireAt: .now.addingTimeInterval(2 * 3_600))
        var moved = old
        moved.fireAt = .now.addingTimeInterval(6 * 3_600)
        let (repo, _, _) = repos()
        repo.currentUserId = { [me] in me }
        var serverAccepted = 0
        repo.rescheduleRow = { _ in serverAccepted += 1 }
        var armedRows: [[ReminderDTO]] = []
        repo.scheduleNotifications = { _, rs, _, _ in armedRows.append(rs) }
        repo.loadRows = { [old] _ in [old] }
        await repo.refresh()
        repo.loadRows = { _ in throw URLError(.networkConnectionLost) }

        try await repo.upsert(moved)
        #expect(serverAccepted == 1)
        await repo.rescheduleNotifications(forSelfUserId: me, events: [])

        #expect(armedRows.count == 1)
        #expect(armedRows.first?.first?.fireAt == moved.fireAt, "armed from the pre-save list")
        #expect(repo.reminders.first?.fireAt == moved.fireAt, "listed at the old time")
    }

    @Test func b14_anEditOfMyOwnReminderWhoseReReadFailedArmsTheNewTime() async throws {
        let old = reminder(title: "Flowers", author: me, target: me, fireAt: .now.addingTimeInterval(2 * 3_600))
        var moved = old
        moved.fireAt = .now.addingTimeInterval(6 * 3_600)
        moved.title = "Tulips"
        let (repo, _, _) = repos()
        repo.currentUserId = { [me] in me }
        repo.upsertRow = { $0 }
        var armedRows: [[ReminderDTO]] = []
        repo.scheduleNotifications = { _, rs, _, _ in armedRows.append(rs) }
        repo.loadRows = { [old] _ in [old] }
        await repo.refresh()
        repo.loadRows = { _ in throw URLError(.networkConnectionLost) }

        try await repo.upsert(moved)
        await repo.rescheduleNotifications(forSelfUserId: me, events: [])

        #expect(armedRows.first == [moved])
    }

    @Test func b14_aPartnerRowKeepsItsTextWhenOnlyTheScheduleWasSaved() async throws {
        let old = reminder(title: "Flowers", author: partner, target: me, fireAt: .now.addingTimeInterval(2 * 3_600))
        var edited = old
        edited.fireAt = .now.addingTimeInterval(6 * 3_600)
        edited.title = "Not mine to change"
        let (repo, _, _) = repos()
        repo.currentUserId = { [me] in me }
        repo.rescheduleRow = { _ in }
        repo.loadRows = { [old] _ in [old] }
        await repo.refresh()
        repo.loadRows = { _ in throw URLError(.networkConnectionLost) }

        try await repo.upsert(edited)

        #expect(repo.reminders.first?.title == "Flowers")
        #expect(repo.reminders.first?.fireAt == edited.fireAt)
    }

    @Test func b14_aPackWhoseReReadFailedIsStillArmed() async throws {
        let pack = [
            reminder(title: "One", author: me, target: me, fireAt: .now.addingTimeInterval(86_400)),
            reminder(title: "Two", author: me, target: me, fireAt: .now.addingTimeInterval(2 * 86_400))
        ]
        let (repo, _, _) = repos()
        repo.insertRows = { _ in }
        repo.loadRows = { _ in [] }
        await repo.refresh()
        repo.loadRows = { _ in throw URLError(.networkConnectionLost) }
        var armedRows: [[ReminderDTO]] = []
        repo.scheduleNotifications = { _, rs, _, _ in armedRows.append(rs) }

        try await repo.importReminders(pack, forSelfUserId: me, events: [])

        #expect(armedRows == [pack])
    }

    // B8 (sm6): Not done reopens the reminder even when two completions were recorded.

    @Test func b8_control_undoOfASingleCompletionReopensTheReminder() {
        let r = reminder(title: "Flowers", author: me, target: me, fireAt: .now.addingTimeInterval(3_600))
        var events = [completion(r, at: .now)]
        #expect(r.isCompleted(in: events))
        let undone = r.currentCompletionEvents(in: events).map(\.id)
        events.removeAll { undone.contains($0.id) }
        #expect(!r.isCompleted(in: events))
    }

    @Test func b8_undoReopensTheReminderEvenWhenBothPartnersMarkedItDone() async throws {
        // Both partners see it, and the events list is not on the realtime feed,
        // so the second tap saw a stale "not done".
        let r = reminder(title: "Flowers", author: partner, target: me, fireAt: .now.addingTimeInterval(3_600))
        let first = completion(r, at: .now.addingTimeInterval(-60))
        let second = completion(r, at: .now)
        let (_, eventsRepo, _) = repos()
        eventsRepo.loadRows = { _ in [second, first] }
        var deleted: [UUID] = []
        eventsRepo.deleteRows = { deleted.append(contentsOf: $0) }
        await eventsRepo.refresh()
        #expect(r.isCompleted(in: eventsRepo.events))

        try await eventsRepo.undoCompletion(of: r)

        #expect(!r.isCompleted(in: eventsRepo.events), "Not done left \(eventsRepo.events.count) completion(s) in place")
        #expect(Set(deleted) == [first.id, second.id])
    }

    @Test func b8_aDoneWhoseReReadFailedStillShowsDone_soASecondTapCannotRecordItTwice() async throws {
        let r = reminder(title: "Flowers", author: me, target: me, fireAt: .now.addingTimeInterval(3_600))
        let (_, eventsRepo, _) = repos()
        eventsRepo.loadRows = { _ in [] }
        await eventsRepo.refresh()
        var inserted = 0
        eventsRepo.insertRow = { _ in inserted += 1 }
        eventsRepo.loadRows = { _ in throw URLError(.networkConnectionLost) }

        try await eventsRepo.createEvent(reminderId: r.id, coupleId: coupleId)

        #expect(inserted == 1)
        #expect(r.isCompleted(in: eventsRepo.events))
    }

    // B12: a Done that did not save is not a positive moment.

    @Test func b12_aDoneThatFailedToSaveIsNotReportedAsDone() async {
        let r = reminder(title: "Flowers", author: me, target: me, fireAt: .now.addingTimeInterval(3_600))
        let (_, eventsRepo, _) = repos()
        eventsRepo.insertRow = { _ in throw URLError(.notConnectedToInternet) }

        let saved = await eventsRepo.markDone(r, coupleId: coupleId)

        #expect(!saved)
        #expect(!r.isCompleted(in: eventsRepo.events))
    }

    @Test func b12_control_aSavedDoneIsReportedAsDone() async {
        let r = reminder(title: "Flowers", author: me, target: me, fireAt: .now.addingTimeInterval(3_600))
        let (_, eventsRepo, _) = repos()
        eventsRepo.insertRow = { _ in }
        eventsRepo.loadRows = { _ in throw URLError(.timedOut) }

        let saved = await eventsRepo.markDone(r, coupleId: coupleId)

        #expect(saved)
        #expect(r.isCompleted(in: eventsRepo.events))
    }
}
