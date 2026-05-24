import Foundation
import OSLog
import Supabase

@MainActor
@Observable
final class ReminderRepository {
    private let supabase = SupabaseService.shared
    private let pairing: PairingService
    private let log = Logger(subsystem: "com.jackwallner.bond", category: "reminders")

    var reminders: [ReminderDTO] = []
    var isLoading = false
    var lastError: String?

    /// Set by the app at launch so the repo can refresh the widget snapshot
    /// after every change. Optional — empty closure is fine for previews/tests.
    var onChange: ([ReminderDTO]) -> Void = { _ in }

    private var realtimeChannel: RealtimeChannelV2?
    /// The couple the active realtime channel is filtered on. Lets us detect
    /// pair/unpair and re-subscribe rather than keeping a channel bound to a
    /// stale (solo) couple id after the user joins their partner.
    private var subscribedCoupleId: UUID?

    init(pairing: PairingService) {
        self.pairing = pairing
    }

    func refresh() async {
        guard let coupleId = pairing.coupleId else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [ReminderDTO] = try await supabase.client
                .from("reminders")
                .select()
                .eq("couple_id", value: coupleId.uuidString)
                .order("fire_at", ascending: true, nullsFirst: false)
                .execute()
                .value
            reminders = rows
            onChange(rows)
            log.info("Refreshed \(rows.count) reminders")
        } catch {
            lastError = error.localizedDescription
            log.error("Refresh failed: \(error.localizedDescription)")
        }
    }

    func upsert(_ reminder: ReminderDTO) async throws {
        let _: ReminderDTO = try await supabase.client
            .from("reminders")
            .upsert(reminder)
            .select()
            .single()
            .execute()
            .value
        log.info("Upserted reminder \(reminder.id)")
        await refresh()
    }

    /// Insert many reminders in a single round-trip, then refresh once. The
    /// per-row [[upsert]] path was acceptable for editor saves but turned
    /// template imports into 14 sequential HTTP calls for 7 reminders.
    func bulkInsert(_ reminders: [ReminderDTO]) async throws {
        guard !reminders.isEmpty else { return }
        try await supabase.client
            .from("reminders")
            .insert(reminders)
            .execute()
        log.info("Bulk-inserted \(reminders.count) reminders")
        await refresh()
    }

    func delete(_ reminder: ReminderDTO) async throws {
        try await supabase.client
            .from("reminders")
            .delete()
            .eq("id", value: reminder.id.uuidString)
            .execute()
        reminders.removeAll { $0.id == reminder.id }
        log.info("Deleted reminder \(reminder.id)")
        onChange(reminders)
    }

    func subscribeRealtime() async {
        guard let coupleId = pairing.coupleId else {
            await unsubscribeRealtime()
            return
        }
        // Already subscribed to *this* couple — nothing to do. But if we're
        // bound to a different couple (e.g. solo → paired), tear down first
        // so the new channel uses the right filter.
        if realtimeChannel != nil {
            guard subscribedCoupleId != coupleId else { return }
            await unsubscribeRealtime()
        }
        let channel = supabase.client.channel("couple:\(coupleId.uuidString)")

        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "reminders",
            filter: "couple_id=eq.\(coupleId.uuidString)"
        )

        await channel.subscribe()
        realtimeChannel = channel
        subscribedCoupleId = coupleId
        log.info("Subscribed to realtime channel for couple \(coupleId)")

        Task {
            for await _ in changes {
                await refresh()
            }
        }
    }

    func unsubscribeRealtime() async {
        if let channel = realtimeChannel {
            await channel.unsubscribe()
            realtimeChannel = nil
            subscribedCoupleId = nil
        }
    }
}
