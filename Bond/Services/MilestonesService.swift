import Foundation
import Supabase

@MainActor
@Observable
final class MilestonesService {
    private let supabase = SupabaseService.shared
    private let pairing: PairingService

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
        } catch {
            lastError = error.localizedDescription
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
        await refresh()
    }

    func delete(_ milestone: MilestoneDTO) async throws {
        try await supabase.client
            .from("milestones")
            .delete()
            .eq("id", value: milestone.id.uuidString)
            .execute()
        milestones.removeAll { $0.id == milestone.id }
    }

    var nextOccurrence: (milestone: MilestoneDTO, date: Date)? {
        milestones
            .map { ($0, $0.nextOccurrence()) }
            .min { $0.1 < $1.1 }
    }
}
