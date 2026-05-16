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
