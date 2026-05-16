import Foundation
import WatchConnectivity

@MainActor
final class WatchConnectivityBridge: NSObject {
    static let shared = WatchConnectivityBridge()

    private weak var repository: ReminderRepository?
    private weak var supabase: SupabaseService?
    private weak var pairing: PairingService?

    private override init() {
        super.init()
    }

    func start(
        repository: ReminderRepository,
        supabase: SupabaseService,
        pairing: PairingService
    ) {
        self.repository = repository
        self.supabase = supabase
        self.pairing = pairing
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    fileprivate nonisolated func handleCreatePayload(_ data: Data) {
        guard let payload = try? JSONDecoder().decode(
            WatchPayload.CreateReminder.self, from: data
        ) else { return }

        Task { @MainActor in
            _ = await createReminder(from: payload)
        }
    }

    /// WCSession's reply handler isn't Sendable; box it so it can cross into
    /// the MainActor task without tripping Swift 6 data-race diagnostics.
    private final class ReplyBox: @unchecked Sendable {
        private let reply: ([String: Any]) -> Void
        init(_ reply: @escaping ([String: Any]) -> Void) { self.reply = reply }
        func callAsFunction(_ payload: [String: Any]) { reply(payload) }
    }

    /// Decodes, creates, and replies with the real outcome so the watch can
    /// stop showing a false "Sent" when the phone silently dropped the payload.
    fileprivate nonisolated func handleCreatePayload(
        _ data: Data,
        reply: @escaping ([String: Any]) -> Void
    ) {
        let box = ReplyBox(reply)
        guard let payload = try? JSONDecoder().decode(
            WatchPayload.CreateReminder.self, from: data
        ) else {
            box(["ok": false, "error": "Couldn't read the reminder."])
            return
        }
        Task { @MainActor in
            let result = await createReminder(from: payload)
            box(["ok": result.ok, "error": result.error ?? ""])
        }
    }

    @MainActor
    @discardableResult
    private func createReminder(
        from payload: WatchPayload.CreateReminder
    ) async -> (ok: Bool, error: String?) {
        guard let supabase, let pairing, let repository,
              let me = supabase.currentUserId,
              let coupleId = pairing.coupleId
        else {
            return (false, "Open Bond on your phone and finish setup first.")
        }

        let fireAt = Date().addingTimeInterval(payload.scheduledOffsetSeconds)
        let language = LoveLanguage(rawValue: payload.loveLanguage) ?? .words

        let reminder = ReminderDTO(
            id: UUID(),
            coupleId: coupleId,
            authorId: me,
            targetId: me,
            title: payload.title,
            body: nil,
            loveLanguage: language,
            triggerType: "one_time",
            fireAt: fireAt,
            rrule: nil,
            geofence: nil,
            windowStart: nil,
            windowEnd: nil,
            status: "scheduled",
            surpriseHiddenFromPartner: false,
            createdAt: nil
        )

        do {
            try await repository.upsert(reminder)
        } catch {
            return (false, "Couldn't save the reminder. Try again.")
        }
        await NotificationScheduler.shared.reschedule(
            forSelfUserId: me, reminders: repository.reminders
        )
        return (true, nil)
    }
}

extension WatchConnectivityBridge: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let data = message[WatchPayload.createReminderKey] as? Data {
            handleCreatePayload(data)
        }
    }

    /// Background path: the watch falls back to `updateApplicationContext`
    /// when the phone isn't reachable. Without this handler those reminders
    /// were silently dropped while the watch still reported "Sent".
    nonisolated func session(
        _ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        if let data = applicationContext[WatchPayload.createReminderKey] as? Data {
            handleCreatePayload(data)
        }
    }

    nonisolated func session(
        _ session: WCSession, didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        if let data = message[WatchPayload.createReminderKey] as? Data {
            handleCreatePayload(data, reply: replyHandler)
        } else {
            replyHandler(["ok": false, "error": "Unrecognized request."])
        }
    }
}
