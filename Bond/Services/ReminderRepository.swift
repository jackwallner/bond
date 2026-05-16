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
        guard let coupleId = pairing.coupleId, realtimeChannel == nil else { return }
        let channel = supabase.client.channel("couple:\(coupleId.uuidString)")

        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "reminders",
            filter: "couple_id=eq.\(coupleId.uuidString)"
        )

        await channel.subscribe()
        realtimeChannel = channel
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
        }
    }
}
