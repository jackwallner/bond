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
            await createReminder(from: payload)
        }
    }

    @MainActor
    private func createReminder(from payload: WatchPayload.CreateReminder) async {
        guard let supabase, let pairing, let repository,
              let me = supabase.currentUserId,
              let coupleId = pairing.coupleId
        else { return }

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

        try? await repository.upsert(reminder)
        await NotificationScheduler.shared.reschedule(
            forSelfUserId: me, reminders: repository.reminders
        )
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

    nonisolated func session(
        _ session: WCSession, didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        if let data = message[WatchPayload.createReminderKey] as? Data {
            handleCreatePayload(data)
        }
        replyHandler(["ok": true])
    }
}
