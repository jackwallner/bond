import Foundation
import OSLog
import Supabase

@MainActor
@Observable
final class MilestonesService {
    private let supabase = SupabaseService.shared
    private let pairing: PairingService
    private let log = Logger(subsystem: "com.jackwallner.bond", category: "milestones")

    var milestones: [MilestoneDTO] = []
    var lastError: String?

    init(pairing: PairingService) {
        self.pairing = pairing
    }

    func refresh() async {
        guard let coupleId = pairing.coupleId else { return }
        do {
            let rows: [MilestoneDTO] = try await supabase.client
                .from("milestones")
                .select()
                .eq("couple_id", value: coupleId.uuidString)
                .execute()
                .value
            milestones = rows
            log.info("Refreshed \(rows.count) milestones")
        } catch {
            lastError = error.localizedDescription
            log.error("Refresh failed: \(error.localizedDescription)")
        }
    }

    func upsert(_ milestone: MilestoneDTO) async throws {
        let _: MilestoneDTO = try await supabase.client
            .from("milestones")
            .upsert(milestone)
            .select()
            .single()
            .execute()
            .value
        log.info("Upserted milestone \(milestone.id)")
        await refresh()
    }

    func delete(_ milestone: MilestoneDTO) async throws {
        try await supabase.client
            .from("milestones")
            .delete()
            .eq("id", value: milestone.id.uuidString)
            .execute()
        milestones.removeAll { $0.id == milestone.id }
        log.info("Deleted milestone \(milestone.id)")
    }

    var nextOccurrence: (milestone: MilestoneDTO, date: Date)? {
        milestones
            .map { ($0, $0.nextOccurrence()) }
            .min { $0.1 < $1.1 }
    }
}
