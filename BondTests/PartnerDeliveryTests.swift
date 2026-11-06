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
