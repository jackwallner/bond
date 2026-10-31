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

    /// Set by the app at launch so the widget snapshot follows the milestone
    /// list. Empty closure is fine for previews/tests.
    @ObservationIgnored
    var onChange: ([MilestoneDTO]) -> Void = { _ in }

    /// Where `refresh()` gets the couple's rows. Tests swap it for a stub.
    @ObservationIgnored
    var loadRows: @MainActor (UUID) async throws -> [MilestoneDTO] = { coupleId in
        try await MilestonesService.fetchRows(coupleId: coupleId)
    }

    /// Lays down the milestone notifications. The flag says whether it may
    /// raise the system permission prompt. Tests swap it for a stub.
    @ObservationIgnored
    var scheduleNotifications: @MainActor ([MilestoneDTO], Bool) async -> Void = { rows, askForPermission in
        await NotificationScheduler.shared.rescheduleMilestones(rows, requestAuthIfNeeded: askForPermission)
    }

    /// Removes one milestone on the server. Tests swap it for a stub.
    @ObservationIgnored
    var deleteRow: @MainActor (UUID) async throws -> Void = { id in
        try await MilestonesService.removeRow(id: id)
    }

    init(pairing: PairingService) {
        self.pairing = pairing
    }

    /// - Parameter requestAuthIfNeeded: whether scheduling may raise the system
    ///   notification prompt. The Milestones tab asks; a launch-time refresh must
    ///   not, so the pre-permission primer still gets to explain first.
    func refresh(requestAuthIfNeeded: Bool = true) async {
        #if DEBUG
        if BondScreenshotSeed.isEnabled { return }
        #endif
        guard let coupleId = pairing.coupleId else { return }
        do {
            let rows = try await loadRows(coupleId)
            milestones = rows
            onChange(rows)
            log.info("Refreshed \(rows.count) milestones")
            await scheduleNotifications(rows, requestAuthIfNeeded)
        } catch {
            lastError = error.localizedDescription
            log.error("Refresh failed: \(error.localizedDescription)")
        }
    }

    private static func fetchRows(coupleId: UUID) async throws -> [MilestoneDTO] {
        try await SupabaseService.shared.client
            .from("milestones")
            .select()
            .eq("couple_id", value: coupleId.uuidString)
            .execute()
            .value
    }

    private static func removeRow(id: UUID) async throws {
        try await SupabaseService.shared.client
            .from("milestones")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
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
        try await deleteRow(milestone.id)
        milestones.removeAll { $0.id == milestone.id }
        onChange(milestones)
        log.info("Deleted milestone \(milestone.id)")
        await scheduleNotifications(milestones, true)
    }

    var nextOccurrence: (milestone: MilestoneDTO, date: Date)? {
        milestones
            .map { ($0, $0.nextOccurrence()) }
            .min { $0.1 < $1.1 }
    }
}
