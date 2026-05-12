import Foundation
import Supabase

@MainActor
@Observable
final class ReminderRepository {
    private let supabase = SupabaseService.shared
    private let pairing: PairingService

    var reminders: [ReminderDTO] = []
    var isLoading = false
    var lastError: String?

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
        } catch {
            lastError = error.localizedDescription
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
        await refresh()
    }

    func delete(_ reminder: ReminderDTO) async throws {
        try await supabase.client
            .from("reminders")
            .delete()
            .eq("id", value: reminder.id.uuidString)
            .execute()
        reminders.removeAll { $0.id == reminder.id }
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
