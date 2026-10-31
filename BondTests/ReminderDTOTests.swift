import Foundation
import Testing
import UserNotifications

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
@MainActor
@Suite(.serialized)
struct LaunchRescheduleTests {
    private let center = UNUserNotificationCenter.current()
    private let me = UUID()
    private let coupleId = UUID()

    private func pendingIdentifiers() async -> Set<String> {
        Set(await center.pendingNotificationRequests().map(\.identifier))
    }

    private func seedPending(_ identifier: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Scheduled by an earlier session"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3_600, repeats: false)
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    private func repository() -> ReminderRepository {
        let pairing = PairingService()
        pairing.coupleId = coupleId
        return ReminderRepository(pairing: pairing)
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

    @Test func failedLaunchFetch_keepsThePendingSchedule() async throws {
        center.removeAllPendingNotificationRequests()
        try await seedPending("scheduled-last-session")
        let repo = repository()
        repo.loadRows = { _ in throw URLError(.notConnectedToInternet) }

        await repo.refresh()
        await repo.rescheduleNotifications(forSelfUserId: me, events: [], requestAuthIfNeeded: false)

        #expect(repo.hasLoaded == false)
        #expect(await pendingIdentifiers().contains("scheduled-last-session"))
        center.removeAllPendingNotificationRequests()
    }

    @Test func successfulFetch_rebuildsTheSchedule() async throws {
        center.removeAllPendingNotificationRequests()
        try await seedPending("stale-from-last-session")
        let reminder = reminderForMe(in: 2)
        let repo = repository()
        repo.loadRows = { _ in [reminder] }

        await repo.refresh()
        await repo.rescheduleNotifications(forSelfUserId: me, events: [], requestAuthIfNeeded: false)

        let pending = await pendingIdentifiers()
        #expect(repo.hasLoaded)
        #expect(pending.contains(reminder.id.uuidString))
        #expect(!pending.contains("stale-from-last-session"))
        center.removeAllPendingNotificationRequests()
    }

    @Test func loadedEmptyList_clearsTheSchedule() async throws {
        center.removeAllPendingNotificationRequests()
        try await seedPending("deleted-on-the-partners-phone")
        let repo = repository()
        repo.loadRows = { _ in [] }

        await repo.refresh()
        await repo.rescheduleNotifications(forSelfUserId: me, events: [], requestAuthIfNeeded: false)

        #expect(repo.hasLoaded)
        #expect(await pendingIdentifiers().isEmpty)
        center.removeAllPendingNotificationRequests()
    }
}
