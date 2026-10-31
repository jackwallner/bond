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
