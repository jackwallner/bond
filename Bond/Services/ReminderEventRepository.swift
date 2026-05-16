import Foundation
import OSLog
import Supabase

@MainActor
@Observable
final class ReminderEventRepository {
    private let supabase = SupabaseService.shared
    private let pairing: PairingService
    private let log = Logger(subsystem: "com.jackwallner.bond", category: "events")

    var events: [ReminderEventDTO] = []
    var lastError: String?

    init(pairing: PairingService) {
        self.pairing = pairing
    }

    func refresh() async {
        guard let coupleId = pairing.coupleId else { return }
        do {
            let rows: [ReminderEventDTO] = try await supabase.client
                .from("reminder_events")
                .select()
                .eq("couple_id", value: coupleId.uuidString)
                .order("fired_at", ascending: false)
                .execute()
                .value
            events = rows
            log.info("Refreshed \(rows.count) events")
        } catch {
            lastError = error.localizedDescription
            log.error("Refresh failed: \(error.localizedDescription)")
        }
    }

    func createEvent(reminderId: UUID, coupleId: UUID) async throws {
        let payload: [String: AnyJSON] = [
            "reminder_id": .string(reminderId.uuidString),
            "couple_id": .string(coupleId.uuidString),
            "fired_at": .string(ISO8601DateFormatter().string(from: Date()))
        ]
        try await supabase.client
            .from("reminder_events")
            .insert(payload)
            .execute()
        log.info("Created event for reminder \(reminderId)")
        await refresh()
    }

    var actedCount: Int {
        events.filter { $0.actedAt != nil }.count
    }

    func eventsPastWeek() -> [ReminderEventDTO] {
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        return events.filter { $0.firedAt >= weekAgo }
    }

    func eventsPastMonth() -> [ReminderEventDTO] {
        let monthAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        return events.filter { $0.firedAt >= monthAgo }
    }
}
