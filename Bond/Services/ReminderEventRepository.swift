import Foundation
import OSLog
import Supabase

@MainActor
@Observable
final class ReminderEventRepository {
    private let pairing: PairingService
    private let log = Logger(subsystem: "com.jackwallner.bond", category: "events")

    var events: [ReminderEventDTO] = []
    var lastError: String?
    /// The couple the current `events` were fetched for.
    private var loadedCoupleId: UUID?

    /// True once a refresh has succeeded for the couple the app is on now. Until
    /// then an empty `events` means "not fetched", not "nothing done", and a
    /// schedule rebuilt from it would ping every handled reminder again.
    var hasLoaded: Bool {
        loadedCoupleId != nil && loadedCoupleId == pairing.coupleId
    }

    /// The completions a schedule rebuild may trust: nil until they were fetched
    /// for the couple the app is on now.
    var loadedEvents: [ReminderEventDTO]? {
        hasLoaded ? events : nil
    }

    /// Where `refresh()` gets the couple's events. Tests swap it for a stub.
    @ObservationIgnored
    var loadRows: @MainActor (UUID) async throws -> [ReminderEventDTO] = { coupleId in
        try await SupabaseService.shared.client
            .from("reminder_events")
            .select()
            .eq("couple_id", value: coupleId.uuidString)
            .order("fired_at", ascending: false)
            .execute()
            .value
    }

    /// Writes one completion. Tests swap it for a stub.
    @ObservationIgnored
    var insertRow: @MainActor (ReminderEventDTO) async throws -> Void = { event in
        let stamp = ISO8601DateFormatter()
        let payload: [String: AnyJSON] = [
            "id": .string(event.id.uuidString),
            "reminder_id": .string(event.reminderId.uuidString),
            "couple_id": .string(event.coupleId.uuidString),
            "fired_at": .string(stamp.string(from: event.firedAt)),
            "acted_at": .string(stamp.string(from: event.actedAt ?? event.firedAt))
        ]
        try await SupabaseService.shared.client
            .from("reminder_events")
            .insert(payload)
            .execute()
    }

    /// Removes completions by id. Tests swap it for a stub.
    @ObservationIgnored
    var deleteRows: @MainActor ([UUID]) async throws -> Void = { ids in
        try await SupabaseService.shared.client
            .from("reminder_events")
            .delete()
            .in("id", values: ids.map(\.uuidString))
            .execute()
    }

    init(pairing: PairingService) {
        self.pairing = pairing
    }

    @discardableResult
    func refresh() async -> Bool {
        #if DEBUG
        if BondScreenshotSeed.isEnabled { return true }
        #endif
        guard let coupleId = pairing.coupleId else { return false }
        do {
            let rows = try await loadRows(coupleId)
            events = rows
            loadedCoupleId = coupleId
            log.info("Refreshed \(rows.count) events")
            return true
        } catch {
            lastError = error.localizedDescription
            log.error("Refresh failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Records "I did this" for a reminder. `acted_at` is what every consumer
    /// keys on (Handled list, streaks, completion stats) - an event without it
    /// is just a firing log entry, so it must be set here or marking done is
    /// invisible everywhere. Throws when the server did not take it.
    func createEvent(reminderId: UUID, coupleId: UUID) async throws {
        let now = Date()
        let event = ReminderEventDTO(
            id: UUID(), reminderId: reminderId, coupleId: coupleId,
            firedAt: now, actedAt: now, reaction: nil
        )
        #if DEBUG
        if BondScreenshotSeed.isEnabled {
            events.insert(event, at: 0)
            BondScreenshotSeed.recordEvent(event)
            return
        }
        #endif
        try await insertRow(event)
        log.info("Created event for reminder \(reminderId)")
        await refresh()
        // The server has it even when the re-read failed. Without it here the
        // reminder still looks open, and a second tap records it twice.
        if !events.contains(where: { $0.id == event.id }) {
            events.insert(event, at: 0)
        }
    }

    /// Marks a reminder done. True only when the completion was saved, which is
    /// what lets the caller count it as a positive moment.
    func markDone(_ reminder: ReminderDTO, coupleId: UUID) async -> Bool {
        do {
            try await createEvent(reminderId: reminder.id, coupleId: coupleId)
            return true
        } catch {
            lastError = error.localizedDescription
            log.error("Marking done failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Undo of "done": removes every completion covering the current period.
    /// Both partners can tick off a shared reminder, so there may be more than
    /// one, and leaving any behind keeps it done.
    func undoCompletion(of reminder: ReminderDTO) async throws {
        let covering = reminder.currentCompletionEvents(in: events)
        guard !covering.isEmpty else { return }
        let ids = covering.map(\.id)
        #if DEBUG
        if BondScreenshotSeed.isEnabled {
            events.removeAll { ids.contains($0.id) }
            for id in ids { BondScreenshotSeed.recordEventRemoved(id) }
            return
        }
        #endif
        try await deleteRows(ids)
        events.removeAll { ids.contains($0.id) }
        log.info("Removed \(ids.count) completion(s) of reminder \(reminder.id)")
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
