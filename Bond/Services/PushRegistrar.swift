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

    /// After the server starts delivering here, so the local copies of what it
    /// now owns go away.
    var onRegistered: (@MainActor () async -> Void)?
    /// A silent push: the couple or something this phone armed itself changed.
    var onRemoteChange: (@MainActor () async -> Void)?

    /// Who is signed in, and the server call. Tests swap them.
    var currentUser: @MainActor () -> UUID? = { SupabaseService.shared.currentUserId }
    var call: @MainActor (_ function: String, _ params: any Encodable & Sendable) async throws -> Void = {
        try await SupabaseService.shared.client.rpc($0, params: $1).execute()
    }

    private let log = Logger(subsystem: "com.jackwallner.bond", category: "push")
    private let defaults: UserDefaults
    private static let tokenKey = "push.token"
    private static let userKey = "push.user"
    /// Before 0019 registration ran once a day; the key is only cleared now.
    private static let legacySyncedKey = "push.synced"
    /// A token a signed-out account still holds on the server, because the
    /// sign-out could not reach it. Kept until another registration moves it.
    nonisolated static let pendingReleaseKey = "push.pendingRelease"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static var environment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    /// Asks for a token when notifications are allowed. Apple answers through the
    /// app delegate, usually straight away from its cache. Runs on every return
    /// to the foreground: registering again is harmless (0019 keeps what is due),
    /// and it restores a device row the server dropped.
    func refresh() async {
        #if DEBUG
        if BondScreenshotSeed.isEnabled || BondScreenshotSeed.isOnboarding { return }
        #endif
        guard currentUser() != nil else { return }
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
        case .denied:
            await unregister()
            await releasePending()
        default:
            await releasePending()
        }
    }

    func store(deviceToken: Data) async {
        await register(token: deviceToken.map { String(format: "%02x", $0) }.joined())
    }

    func register(token: String, calendar: Calendar = .current, timezone: TimeZone = .current) async {
        guard let me = currentUser() else { return }
        let wasServed = serverDelivers(for: me)
        let registration = PushRegistration(
            token: token, env: Self.environment, timezone: timezone.identifier, calendar: calendar,
            armedLocally: !wasServed
        )
        do {
            try await call("register_push_device", registration)
            defaults.set(token, forKey: Self.tokenKey)
            defaults.set(me.uuidString, forKey: Self.userKey)
            defaults.removeObject(forKey: Self.legacySyncedKey)
            log.info("Registered for push")
            await releasePending(movedBy: token)
            if !wasServed { await onRegistered?() }
        } catch {
            log.error("Push registration failed: \(error.localizedDescription)")
            // The server may have taken it and the answer got lost. A phone it was
            // not serving still arms everything itself, so take the token back
            // rather than have both deliver. One it was serving keeps its row.
            if !wasServed {
                do {
                    try await call("unregister_push_device", ["p_token": token])
                } catch {
                    // Both may deliver until the next registration settles it.
                    log.error("Taking the token back failed: \(error.localizedDescription)")
                    defaults.set(token, forKey: Self.pendingReleaseKey)
                }
            }
        }
    }

    /// Whether the server delivers this user's partner-written reminders here.
    func serverDelivers(for user: UUID) -> Bool {
        defaults.string(forKey: Self.userKey) == user.uuidString
    }

    /// Whether a signed-out account may still reach this phone. Read from the
    /// notification delegate, off the main actor.
    nonisolated static func hasPendingRelease(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: pendingReleaseKey) != nil
    }

    /// For sign-out and for notifications being turned off, while the session
    /// still exists. When the server cannot be reached the token is remembered,
    /// and the next registration, by whoever is signed in then, takes it over.
    func unregister() async {
        if let token = defaults.string(forKey: Self.tokenKey) {
            do {
                try await call("unregister_push_device", ["p_token": token])
            } catch {
                log.error("Unregistering failed, kept for the next sign-in: \(error.localizedDescription)")
                defaults.set(token, forKey: Self.pendingReleaseKey)
            }
        }
        forget()
    }

    /// Moves a token a signed-out account still holds to this account, then lets
    /// it go. A token this phone just registered was moved already.
    func releasePending(movedBy registered: String? = nil) async {
        guard let pending = defaults.string(forKey: Self.pendingReleaseKey) else { return }
        if pending == registered {
            defaults.removeObject(forKey: Self.pendingReleaseKey)
            return
        }
        guard currentUser() != nil else { return }
        do {
            try await call("register_push_device", PushRegistration(
                token: pending, env: Self.environment, timezone: TimeZone.current.identifier, calendar: .current
            ))
            try await call("unregister_push_device", ["p_token": pending])
            defaults.removeObject(forKey: Self.pendingReleaseKey)
        } catch {
            log.error("Releasing the old account's token failed: \(error.localizedDescription)")
        }
    }

    /// Clears the promise, so the next schedule rebuild arms everything locally.
    func forget() {
        for key in [Self.tokenKey, Self.userKey, Self.legacySyncedKey] {
            defaults.removeObject(forKey: key)
        }
    }

    /// A silent push: an unpair or a pairing may have moved the couple, or the
    /// partner removed a place this phone armed. The couple is looked up again
    /// every time, because the inviter keeps the couple id when unpairing, then
    /// what this phone armed is rebuilt from the fresh list.
    static func rebuildAfterSilentPush(
        pairing: PairingService,
        repo: ReminderRepository,
        events: ReminderEventRepository,
        bootstrap: @MainActor () async -> Void = { await SupabaseService.shared.bootstrap() }
    ) async {
        await bootstrap()
        await pairing.loadCouple()
        guard let me = SupabaseService.shared.currentUserId else { return }
        await repo.catchUp(forSelfUserId: me) {
            await events.refresh()
            return events.loadedEvents
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

/// The arguments of `register_push_device`. The first weekday is the one the
/// phone's weekly completions count from (`ReminderCompletion`), so the server's
/// "done this week" (0017) starts on the same day. A phone the server already
/// served armed nothing itself, even if its token is new to the server.
struct PushRegistration: Encodable, Equatable, Sendable {
    let token: String
    let env: String
    let timezone: String
    let firstWeekday: Int
    let armedLocally: Bool

    init(token: String, env: String, timezone: String, calendar: Calendar, armedLocally: Bool = true) {
        self.token = token
        self.env = env
        self.timezone = timezone
        self.firstWeekday = calendar.firstWeekday
        self.armedLocally = armedLocally
    }

    private enum CodingKeys: String, CodingKey {
        case token = "p_token"
        case env = "p_env"
        case timezone = "p_timezone"
        case firstWeekday = "p_first_weekday"
        case armedLocally = "p_armed_locally"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(token, forKey: .token)
        try c.encode(env, forKey: .env)
        try c.encode(timezone, forKey: .timezone)
        try c.encode(firstWeekday, forKey: .firstWeekday)
        try c.encode(armedLocally, forKey: .armedLocally)
    }
}
