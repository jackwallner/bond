import Foundation
import OSLog
import Supabase
import UIKit
import UserNotifications

/// The APNs token and the promise that goes with it: once the server has this
/// phone's token it delivers partner-written reminders here, and the scheduler
/// stops arming them locally. Until then local notifications stay on, so a failed
/// registration costs nothing and no reminder arrives twice.
@MainActor
final class PushRegistrar {
    static let shared = PushRegistrar()

    /// After registering, so the local copies of what the server now owns go away.
    var onRegistered: (@MainActor () async -> Void)?
    /// A silent push: the partner changed something this phone has to arm itself.
    var onRemoteChange: (@MainActor () async -> Void)?

    private let log = Logger(subsystem: "com.jackwallner.bond", category: "push")
    private let defaults = UserDefaults.standard
    private static let tokenKey = "push.token"
    private static let userKey = "push.user"
    private static let syncedKey = "push.synced"

    private init() {}

    private static var environment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    /// Asks for a token when notifications are allowed. Apple answers through the
    /// app delegate, usually straight away from its cache.
    func refresh() async {
        #if DEBUG
        if BondScreenshotSeed.isEnabled || BondScreenshotSeed.isOnboarding { return }
        #endif
        guard SupabaseService.shared.currentUserId != nil else { return }
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
        case .denied:
            await unregister()
        default:
            break
        }
    }

    func store(deviceToken: Data) async {
        guard let me = SupabaseService.shared.currentUserId else { return }
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        let timezone = TimeZone.current.identifier
        // Once a day is enough: every registration re-reads this user's schedule.
        let day = Date.now.formatted(.iso8601.year().month().day())
        let sync = [token, me.uuidString, timezone, day].joined(separator: "|")
        guard defaults.string(forKey: Self.syncedKey) != sync else { return }
        do {
            try await SupabaseService.shared.client
                .rpc("register_push_device", params: [
                    "p_token": token, "p_env": Self.environment, "p_timezone": timezone
                ])
                .execute()
            defaults.set(token, forKey: Self.tokenKey)
            defaults.set(me.uuidString, forKey: Self.userKey)
            defaults.set(sync, forKey: Self.syncedKey)
            log.info("Registered for push")
            await onRegistered?()
        } catch {
            log.error("Push registration failed: \(error.localizedDescription)")
        }
    }

    /// Whether the server delivers this user's partner-written reminders here.
    func serverDelivers(for user: UUID) -> Bool {
        defaults.string(forKey: Self.userKey) == user.uuidString
    }

    /// For sign-out and for notifications being turned off, while the session
    /// still exists. A failure is left to `forget`: the row points at a phone
    /// whose next sign-in takes the token over.
    func unregister() async {
        if let token = defaults.string(forKey: Self.tokenKey) {
            try? await SupabaseService.shared.client
                .rpc("unregister_push_device", params: ["p_token": token])
                .execute()
        }
        forget()
    }

    /// Clears the promise, so the next schedule rebuild arms everything locally.
    func forget() {
        for key in [Self.tokenKey, Self.userKey, Self.syncedKey] {
            defaults.removeObject(forKey: key)
        }
    }
}

/// APNs hands the token and silent pushes to the app delegate and nowhere else.
final class BondAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in await PushRegistrar.shared.store(deviceToken: deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Logger(subsystem: "com.jackwallner.bond", category: "push")
            .error("APNs registration failed: \(error.localizedDescription)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        await PushRegistrar.shared.onRemoteChange?()
        return .newData
    }
}
