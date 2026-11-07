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

    /// Who is signed in, which decides how a save reaches the server.
    @ObservationIgnored
    var currentUserId: @MainActor () -> UUID? = { SupabaseService.shared.currentUserId }

    /// Moves a reminder the partner wrote. Tests swap it for a stub.
    @ObservationIgnored
    var rescheduleRow: @MainActor (ReminderDTO) async throws -> Void = { reminder in
        try await SupabaseService.shared.client
            .rpc("reschedule_reminder", params: RescheduleReminderParams(reminder))
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

    /// Who the schedule is for and which completions it should honour, for the
    /// changes that arrive outside any screen (the realtime feed, the watch).
    /// The app sets it at launch; without one (previews, tests) `rearm()` does
    /// nothing.
    /// `events` is nil while the completions have not been fetched.
    @ObservationIgnored
    var armingContext: @MainActor () -> (user: UUID, events: [ReminderEventDTO]?)? = { nil }

    private var realtimeChannel: RealtimeChannelV2?
    /// The couple the active realtime channel is filtered on. Lets us detect
    /// pair/unpair and re-subscribe rather than keeping a channel bound to a
    /// stale (solo) couple id after the user joins their partner.
    private var subscribedCoupleId: UUID?

    init(pairing: PairingService) {
        self.pairing = pairing
    }

    @discardableResult
    func refresh() async -> Bool {
        #if DEBUG
        if BondScreenshotSeed.isEnabled { return true }
        #endif
        guard let coupleId = pairing.coupleId else { return false }
        isLoading = true
        defer { isLoading = false }
        do {
            let rows = try await loadRows(coupleId)
            reminders = rows
            loadedCoupleId = coupleId
            onChange(rows)
            log.info("Refreshed \(rows.count) reminders")
            return true
        } catch {
            lastError = error.localizedDescription
            log.error("Refresh failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Puts rows the server just accepted into the loaded list when the re-read
    /// after the write failed, so the list and the schedule rebuilt from it show
    /// the save instead of what was there before it. Before any list loaded
    /// there is nothing to patch: the rebuild waits for a fetch anyway.
    private func keepSaved(_ saved: [ReminderDTO]) {
        guard hasLoaded else { return }
        for row in saved {
            if let index = reminders.firstIndex(where: { $0.id == row.id }) {
                reminders[index] = row
            } else {
                reminders.append(row)
            }
        }
        onChange(reminders)
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
    /// every scheduled reminder. The completions are held to the same rule
    /// (`events` is nil until they were fetched): without them every handled
    /// one-shot and every daily random reminder done today pings again.
    func rescheduleNotifications(
        forSelfUserId me: UUID,
        events: [ReminderEventDTO]?,
        requestAuthIfNeeded: Bool = true
    ) async {
        guard hasLoaded, let events else { return }
        await scheduleNotifications(me, reminders, events, requestAuthIfNeeded)
    }

    /// Rebuilds the schedule from the list as it stands, for the callers that
    /// have no screen to read the signed-in user and the completions from. Never
    /// raises the permission prompt: the notification primer owns that.
    func rearm() async {
        guard let context = armingContext() else { return }
        await rescheduleNotifications(
            forSelfUserId: context.user, events: context.events, requestAuthIfNeeded: false
        )
    }

    /// A change another device made, delivered by the realtime feed while the
    /// app is open. The list is only half of it: the phone locking afterwards is
    /// not a return to the foreground, so a reminder the partner just added (or
    /// moved, or deleted) is armed (or disarmed) here, not at the next catch-up.
    func handleRemoteChange() async {
        await refresh()
        await rearm()
    }

    /// Catches up after the app returns to the foreground. The realtime feed is
    /// not replayed after the app was suspended, so what the partner added in the
    /// meantime is only on the server: re-read the list and the completions, then
    /// re-arm the notifications from them. A failed fetch leaves the schedule
    /// alone (see `rescheduleNotifications`), and the permission prompt is left
    /// to the notification primer.
    func catchUp(
        forSelfUserId me: UUID,
        refreshEvents: () async -> [ReminderEventDTO]?
    ) async {
        await refresh()
        let events = await refreshEvents()
        await rescheduleNotifications(forSelfUserId: me, events: events, requestAuthIfNeeded: false)
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
        // The row is the partner's, so only its schedule is this user's to change.
        if let me = currentUserId(), reminder.authorId != me {
            try await rescheduleRow(reminder)
            log.info("Rescheduled reminder \(reminder.id)")
            let reread = await refresh()
            if !reread, let stored = reminders.first(where: { $0.id == reminder.id }) {
                keepSaved([stored.withSchedule(of: reminder)])
            }
            return
        }
        let saved = try await upsertRow(reminder)
        log.info("Upserted reminder \(reminder.id)")
        let reread = await refresh()
        if !reread { keepSaved([saved]) }
    }

    /// Writes one reminder and returns the stored row. Tests swap it for a stub.
    @ObservationIgnored
    var upsertRow: @MainActor (ReminderDTO) async throws -> ReminderDTO = { reminder in
        try await SupabaseService.shared.client
            .from("reminders")
            .upsert(reminder)
            .select()
            .single()
            .execute()
            .value
    }

    /// Insert many reminders in a single round-trip, then refresh once. The
    /// per-row [[upsert]] path was acceptable for editor saves but turned
    /// template imports into 14 sequential HTTP calls for 7 reminders.
    func bulkInsert(_ reminders: [ReminderDTO]) async throws {
        guard !reminders.isEmpty else { return }
        try await insertRows(reminders)
        log.info("Bulk-inserted \(reminders.count) reminders")
        let reread = await refresh()
        if !reread { keepSaved(reminders) }
    }

    /// Adds a batch (a template pack) for the signed-in user and arms it. The
    /// schedule is only rebuilt on launch and when the Reminders tab appears, and
    /// neither happens when a sheet over the tab closes, so without this the pack
    /// would start firing after the next relaunch or tab revisit.
    func importReminders(
        _ reminders: [ReminderDTO],
        forSelfUserId me: UUID,
        events: [ReminderEventDTO]?
    ) async throws {
        try await bulkInsert(reminders)
        await rescheduleNotifications(forSelfUserId: me, events: events)
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
                await handleRemoteChange()
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

/// The arguments of the `reschedule_reminder` RPC. Every one goes out even when
/// nil: PostgREST finds the function by its argument names, and a cleared field
/// has to clear.
struct RescheduleReminderParams: Encodable, Sendable {
    let reminder: ReminderDTO

    init(_ reminder: ReminderDTO) {
        self.reminder = reminder
    }

    private enum CodingKeys: String, CodingKey {
        case id = "p_id"
        case triggerType = "p_trigger_type"
        case fireAt = "p_fire_at"
        case rrule = "p_rrule"
        case geofence = "p_geofence"
        case windowStart = "p_window_start"
        case windowEnd = "p_window_end"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(reminder.id, forKey: .id)
        try c.encode(reminder.triggerType, forKey: .triggerType)
        try c.encode(reminder.fireAt, forKey: .fireAt)
        try c.encode(reminder.rrule, forKey: .rrule)
        try c.encode(reminder.geofence, forKey: .geofence)
        try c.encode(reminder.windowStart, forKey: .windowStart)
        try c.encode(reminder.windowEnd, forKey: .windowEnd)
    }
}
