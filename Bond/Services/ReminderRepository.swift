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
    /// The couple the current `reminders` were fetched for.
    private var loadedCoupleId: UUID?

    /// True once a refresh has succeeded for the couple the app is on now.
    /// Until then an empty `reminders` means "not fetched yet", not "the couple
    /// has none", and after sign-out or a pairing change the old list is not
    /// the new couple's.
    var hasLoaded: Bool {
        loadedCoupleId != nil && loadedCoupleId == pairing.coupleId
    }

    /// Where `refresh()` gets the couple's rows. Tests swap it for a stub.
    @ObservationIgnored
    var loadRows: @MainActor (UUID) async throws -> [ReminderDTO] = { coupleId in
        try await ReminderRepository.fetchRows(coupleId: coupleId)
    }

    /// Writes a batch of new reminders in one request. Tests swap it for a stub.
    @ObservationIgnored
    var insertRows: @MainActor ([ReminderDTO]) async throws -> Void = { reminders in
        try await SupabaseService.shared.client
            .from("reminders")
            .insert(reminders)
            .execute()
    }

    /// Lays down the on-device notifications for the signed-in user from the
    /// given list and events; the flag says whether it may raise the system
    /// permission prompt. Tests swap it for a stub, because a test host has no
    /// notification permission and cannot add real requests.
    @ObservationIgnored
    var scheduleNotifications: @MainActor (UUID, [ReminderDTO], [ReminderEventDTO], Bool) async -> Void = {
        me, reminders, events, askForPermission in
        await NotificationScheduler.shared.reschedule(
            forSelfUserId: me,
            reminders: reminders,
            events: events,
            requestAuthIfNeeded: askForPermission
        )
    }

    /// Set by the app at launch so the repo can refresh the widget snapshot
    /// after every change. Optional - empty closure is fine for previews/tests.
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
        #if DEBUG
        if BondScreenshotSeed.isEnabled { return }
        #endif
        guard let coupleId = pairing.coupleId else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let rows = try await loadRows(coupleId)
            reminders = rows
            loadedCoupleId = coupleId
            onChange(rows)
            log.info("Refreshed \(rows.count) reminders")
        } catch {
            lastError = error.localizedDescription
            log.error("Refresh failed: \(error.localizedDescription)")
        }
    }

    private static func fetchRows(coupleId: UUID) async throws -> [ReminderDTO] {
        try await SupabaseService.shared.client
            .from("reminders")
            .select()
            .eq("couple_id", value: coupleId.uuidString)
            .order("fire_at", ascending: true, nullsFirst: false)
            .execute()
            .value
    }

    /// Rebuilds the on-device notification schedule from the loaded list.
    /// A rebuild replaces every pending notification with what `reminders`
    /// says, so it waits for a successful fetch: before one the list is the
    /// empty starting value, and a launch whose fetch failed would cancel
    /// every scheduled reminder.
    func rescheduleNotifications(
        forSelfUserId me: UUID,
        events: [ReminderEventDTO],
        requestAuthIfNeeded: Bool = true
    ) async {
        guard hasLoaded else { return }
        await scheduleNotifications(me, reminders, events, requestAuthIfNeeded)
    }

    func upsert(_ reminder: ReminderDTO) async throws {
        #if DEBUG
        if BondScreenshotSeed.isEnabled {
            var saved = reminder
            if saved.createdAt == nil { saved.createdAt = Date() }
            if let index = reminders.firstIndex(where: { $0.id == saved.id }) {
                reminders[index] = saved
            } else {
                reminders.append(saved)
            }
            BondScreenshotSeed.recordReminder(saved)
            onChange(reminders)
            return
        }
        #endif
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
        try await insertRows(reminders)
        log.info("Bulk-inserted \(reminders.count) reminders")
        await refresh()
    }

    /// Adds a batch (a template pack) for the signed-in user.
    func importReminders(
        _ reminders: [ReminderDTO],
        forSelfUserId me: UUID,
        events: [ReminderEventDTO]
    ) async throws {
        try await bulkInsert(reminders)
    }

    func delete(_ reminder: ReminderDTO) async throws {
        #if DEBUG
        if BondScreenshotSeed.isEnabled {
            reminders.removeAll { $0.id == reminder.id }
            BondScreenshotSeed.recordReminderRemoved(reminder.id)
            onChange(reminders)
            return
        }
        #endif
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
        #if DEBUG
        if BondScreenshotSeed.isEnabled { return }
        #endif
        guard let coupleId = pairing.coupleId else {
            await unsubscribeRealtime()
            return
        }
        // Already subscribed to *this* couple - nothing to do. But if we're
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
