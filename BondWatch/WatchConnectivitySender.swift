import Foundation
import OSLog
import WatchConnectivity

@MainActor
@Observable
final class WatchConnectivitySender: NSObject {
    static let shared = WatchConnectivitySender()
    private let log = Logger(subsystem: "com.jackwallner.bond.watch", category: "connectivity")

    var lastError: String?
    var isReachable = false

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
        guard let data = try? JSONEncoder().encode(payload) else {
            lastError = "Failed to encode payload."
            return false
        }

        let session = WCSession.default
        guard session.activationState == .activated else {
            lastError = "Watch session not active."
            return false
        }

        if session.isReachable {
            return await sendNow(data: data)
        }
        do {
            try session.updateApplicationContext(
                [WatchPayload.createReminderKey: data]
            )
            log.info("Sent reminder via application context (background)")
            return true
        } catch {
            lastError = error.localizedDescription
            log.error("Failed to send via context: \(error.localizedDescription)")
            return false
        }
    }

    private nonisolated func sendNow(data: Data) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            WCSession.default.sendMessage(
                [WatchPayload.createReminderKey: data],
                replyHandler: { response in
                    let ok = (response["ok"] as? Bool) ?? false
                    if !ok {
                        let message = (response["error"] as? String) ?? "Couldn't save on your phone."
                        Task { @MainActor in
                            WatchConnectivitySender.shared.lastError = message
                        }
                    }
                    cont.resume(returning: ok)
                },
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
        if let error {
            Task { @MainActor in self.lastError = error.localizedDescription }
        }
    }

    // These two are iOS-only WCSessionDelegate requirements — they are
    // marked unavailable on watchOS, so the watch target must not declare them.
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }
    #endif

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }
}
