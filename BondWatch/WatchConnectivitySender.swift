import Foundation
import WatchConnectivity

@MainActor
final class WatchConnectivitySender: NSObject, ObservableObject {
    static let shared = WatchConnectivitySender()

    @Published var lastError: String?
    @Published var isReachable = false

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func sendDictatedReminder(title: String, language: LoveLanguage) async -> Bool {
        let payload = WatchPayload.CreateReminder(
            title: title,
            loveLanguage: language.rawValue,
            scheduledOffsetSeconds: 60 * 60 // default: fire one hour from now
        )
        guard let data = try? JSONEncoder().encode(payload) else { return false }

        let session = WCSession.default
        guard session.activationState == .activated else {
            lastError = "Watch session not active."
            return false
        }
        let reachable = session.isReachable

        if reachable {
            return await sendNow(data: data)
        }
        do {
            try session.updateApplicationContext(
                [WatchPayload.createReminderKey: data]
            )
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private nonisolated func sendNow(data: Data) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            WCSession.default.sendMessage(
                [WatchPayload.createReminderKey: data],
                replyHandler: { _ in cont.resume(returning: true) },
                errorHandler: { err in
                    let message = err.localizedDescription
                    Task { @MainActor in
                        WatchConnectivitySender.shared.lastError = message
                    }
                    cont.resume(returning: false)
                }
            )
        }
    }
}

extension WatchConnectivitySender: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }
}
