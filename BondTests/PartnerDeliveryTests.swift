import Foundation
import Testing
@testable import Bond

@MainActor
struct PartnerDeliveryTests {
    private let me = UUID()
    private let partner = UUID()

    private func reminder(author: UUID, target: UUID, type: String = "one_time") -> ReminderDTO {
        ReminderDTO(
            id: UUID(), coupleId: UUID(), authorId: author, targetId: target,
            title: "Flowers", body: nil, loveLanguage: .gifts, triggerType: type,
            fireAt: Date(timeIntervalSince1970: 2_000_000_000), rrule: nil, geofence: nil,
            windowStart: nil, windowEnd: nil, status: "scheduled",
            surpriseHiddenFromPartner: false, createdAt: nil
        )
    }

    @Test func withoutServerDeliveryEverythingForMeArmsLocally() {
        let arms = NotificationScheduler.armsLocally
        #expect(arms(reminder(author: me, target: me), me, false))
        #expect(arms(reminder(author: partner, target: me), me, false))
        #expect(!arms(reminder(author: me, target: partner), me, false))
    }

    @Test func serverDeliveryTakesOverOnlyWhatThePartnerWroteWithATime() {
        let arms = NotificationScheduler.armsLocally
        #expect(arms(reminder(author: me, target: me), me, true))
        #expect(!arms(reminder(author: partner, target: me), me, true))
        #expect(arms(reminder(author: partner, target: me, type: "location"), me, true))
        #expect(!arms(reminder(author: me, target: partner), me, true))
    }

    @Test func aPartnersReminderIsRescheduledNotUpserted() async throws {
        let repo = ReminderRepository(pairing: PairingService())
        repo.currentUserId = { [me] in me }
        var moved: [UUID] = []
        repo.rescheduleRow = { moved.append($0.id) }
        let row = reminder(author: partner, target: me)
        try await repo.upsert(row)
        #expect(moved == [row.id])
    }

    @Test func rescheduleSendsEveryArgumentEvenWhenCleared() throws {
        let data = try JSONEncoder().encode(RescheduleReminderParams(reminder(author: partner, target: me)))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(json.keys) == [
            "p_id", "p_trigger_type", "p_fire_at", "p_rrule", "p_geofence", "p_window_start", "p_window_end"
        ])
        #expect(json["p_rrule"] is NSNull)
    }
}

// MARK: - State machine audit 2026-11-06: B15 (sm3), one week on the phone and the server

struct WeekStartTests {
    private func pacific(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func calendar(firstWeekday: Int) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        cal.firstWeekday = firstWeekday
        cal.minimumDaysInFirstWeek = 1
        return cal
    }

    private func body(_ registration: PushRegistration) throws -> [String: Any] {
        let data = try JSONEncoder().encode(registration)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    @Test func b15_theServerIsToldTheWeekThePhoneCountsDoneFrom() throws {
        // en_US: the week starts on Sunday, so a weekly reminder done on Saturday
        // is open again on Sunday on the phone. The server (0017 reminder_done_at)
        // starts the week at the first weekday it was sent.
        let sundayFirst = calendar(firstWeekday: 1)
        let weekly = ReminderDTO(
            id: UUID(), coupleId: UUID(), authorId: UUID(), targetId: UUID(),
            title: "Date night", body: nil, loveLanguage: .time, triggerType: "recurring",
            fireAt: pacific(2026, 11, 1, 9), rrule: "FREQ=WEEKLY", geofence: nil,
            windowStart: nil, windowEnd: nil, status: "scheduled",
            surpriseHiddenFromPartner: false, createdAt: nil
        )
        #expect(weekly.currentPeriodStart(at: pacific(2026, 11, 8, 10), calendar: sundayFirst) == pacific(2026, 11, 8))

        let registration = PushRegistration(token: "t", env: "sandbox", timezone: "America/Los_Angeles", calendar: sundayFirst)
        #expect(try body(registration)["p_first_weekday"] as? Int == 1)
        #expect(try body(registration)["p_token"] as? String == "t")
        let mondayFirst = PushRegistration(token: "t", env: "sandbox", timezone: "UTC", calendar: calendar(firstWeekday: 2))
        #expect(try body(mondayFirst)["p_first_weekday"] as? Int == 2)
        // Without the week the call matches the three-argument function the store builds use.
        #expect(try body(registration.withoutWeek).keys.sorted() == ["p_env", "p_timezone", "p_token"])
    }
}
