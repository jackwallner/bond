import Foundation
import OSLog
import Supabase

@MainActor
@Observable
final class SupabaseService {
    static let shared = SupabaseService()
    private let log = Logger(subsystem: "com.jackwallner.bond", category: "auth")

    let client: SupabaseClient

    var currentUserId: UUID?
    var isAnonymous: Bool = false
    var isAuthenticated: Bool { currentUserId != nil }

    private var bootstrapTask: Task<Void, Never>?

    private init() {
        self.client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey
        )
    }

    /// Idempotent session bootstrap. The first caller kicks off
    /// `restoreSession()`; concurrent callers await the same task. This
    /// prevents the launch race where `init` and `RootView.task` both fire
    /// `signInAnonymously()` independently and create two anon users - the
    /// client session ends up signed in as one while `currentUserId` caches
    /// the other, which makes `p_user <> auth.uid()` RPC checks fail with
    /// "unauthorized".
    func bootstrap() async {
        if let bootstrapTask {
            await bootstrapTask.value
            return
        }
        let task = Task { await self.restoreSession() }
        bootstrapTask = task
        await task.value
    }

    /// Force a fresh bootstrap attempt. `bootstrap()` caches its task, so once
    /// the first attempt finishes - even if it failed to establish a session
    /// (e.g. the device was offline at first launch, so anonymous sign-in
    /// couldn't run) - re-calling it just re-awaits the failed task. The
    /// loading screen's "Try again" calls this so a retry actually re-attempts.
    func retryBootstrap() async {
        bootstrapTask = nil
        await bootstrap()
    }

    /// Restore a cached session, or silently start an anonymous one so every
    /// user has a backing Supabase identity without seeing a sign-in screen.
    /// Apple Sign-In is reserved for opt-in upgrades (pairing, account
    /// recovery), not for first launch.
    func restoreSession() async {
        await restoreSession(
            loadSession: { [client] in
                let session = try await client.auth.session
                return RestoredIdentity(userId: session.user.id, isAnonymous: session.user.isAnonymous)
            },
            startFreshSession: { await self.signInAnonymously() }
        )
    }

    /// Who the stored session says is signed in.
    struct RestoredIdentity: Equatable {
        let userId: UUID
        let isAnonymous: Bool
    }

    /// `restoreSession()` with its two outside steps handed in, so tests can
    /// fail the load without a network.
    func restoreSession(
        loadSession: () async throws -> RestoredIdentity,
        startFreshSession: () async -> Void
    ) async {
        do {
            let identity = try await loadSession()
            currentUserId = identity.userId
            isAnonymous = identity.isAnonymous
            log.info("Session restored for user \(identity.userId) (anon: \(identity.isAnonymous))")
        } catch {
            guard Self.shouldStartFreshSession(after: error) else {
                log.notice("Session restore interrupted, keeping the stored session: \(error.localizedDescription)")
                return
            }
            log.notice("No cached session - signing in anonymously")
            await startFreshSession()
        }
    }

    /// A load that failed because a request never completed (offline, timeout,
    /// connection lost) says nothing about the stored session: it may be intact
    /// and only need its token refreshed. Signing in as a new anonymous user then
    /// replaces it and strands the account it belongs to, so the launch waits
    /// for "Try again" instead.
    nonisolated static func shouldStartFreshSession(after error: Error) -> Bool {
        !requestNeverCompleted(error)
    }

    /// A link that failed because a request never completed says nothing about
    /// whether the Apple identity belongs to someone else. Signing in then would,
    /// for an identity nobody has used, create a brand new empty account and orphan
    /// the anonymous user's couple and reminders, so only a failure the server
    /// answered may fall back to a plain sign-in.
    nonisolated static func shouldFallBackToSignIn(after error: Error) -> Bool {
        !requestNeverCompleted(error)
    }

    nonisolated private static func requestNeverCompleted(_ error: Error) -> Bool {
        error is CancellationError || error is URLError || (error as NSError).domain == NSURLErrorDomain
    }

    func signInAnonymously() async {
        do {
            let session = try await client.auth.signInAnonymously()
            currentUserId = session.user.id
            isAnonymous = true
            log.info("Signed in anonymously - user \(session.user.id)")
        } catch {
            // Don't nuke an already-restored session on failure: restoreSession()
            // and this method can race at launch, and clearing currentUserId here
            // would leave the user stuck on the loading screen even though a valid
            // session existed.
            log.error("Anonymous sign-in failed: \(error.localizedDescription)")
        }
    }

    func signInWithApple(idToken: String, nonce: String) async throws {
        let credentials = OpenIDConnectCredentials(
            provider: .apple, idToken: idToken, nonce: nonce
        )
        try await signInWithApple(
            link: { [client] in
                let session = try await client.auth.linkIdentityWithIdToken(credentials: credentials)
                return RestoredIdentity(userId: session.user.id, isAnonymous: session.user.isAnonymous)
            },
            signIn: { [client] in
                let session = try await client.auth.signInWithIdToken(credentials: credentials)
                return RestoredIdentity(userId: session.user.id, isAnonymous: session.user.isAnonymous)
            }
        )
    }

    /// `signInWithApple(idToken:nonce:)` with its two outside steps handed in, so
    /// tests can fail the link without a network.
    func signInWithApple(
        link: () async throws -> RestoredIdentity,
        signIn: () async throws -> RestoredIdentity
    ) async throws {
        // When the user is already in an anonymous session, link the Apple
        // identity to *that* user rather than minting a new one. Without
        // this branch, every "upgrade your account" flow silently swapped
        // auth.uid() and orphaned the user's reminders, milestones, and
        // couple row to the abandoned anon identity.
        let identity: RestoredIdentity
        if isAnonymous {
            do {
                identity = try await link()
                log.info("Linked Apple identity to anonymous user \(identity.userId)")
            } catch where Self.shouldFallBackToSignIn(after: error) {
                // If linking fails because the Apple identity is *already*
                // attached to a different Supabase user (e.g. user previously
                // signed in with Apple on another device), fall back to a
                // straight sign-in so they can recover that account. Their
                // anonymous-session data is lost in that case, which is the
                // correct tradeoff - the recoverable account wins.
                log.notice("linkIdentityWithIdToken failed (\(error.localizedDescription)); falling back to signInWithIdToken")
                identity = try await signIn()
            }
        } else {
            identity = try await signIn()
        }
        currentUserId = identity.userId
        isAnonymous = identity.isAnonymous
        log.info("Signed in with Apple - user \(identity.userId)")
    }

    func signOut() async {
        try? await client.auth.signOut()
        currentUserId = nil
        isAnonymous = false
        bootstrapTask = nil
        log.info("Signed out")
        // Immediately establish a fresh anonymous session so the router
        // doesn't strand the user on the loading spinner. Sign-out is a
        // "new guest session" event, not a terminal state - without this,
        // `RootView` keeps rendering `.loading` because nothing else
        // re-runs `bootstrap()`.
        await bootstrap()
    }

    /// Permanently delete the current account and all its server-side data
    /// (App Store Guideline 5.1.1(v)). The `delete_account` RPC deletes the
    /// caller's `auth.users` row; FK cascades take out their profile, reminders,
    /// check-ins, and subscription mirror. If the caller was paired, the RPC
    /// first hands the shared couple to the partner as a solo couple, so the
    /// partner keeps their own reminders, the shared milestones, and their
    /// account. We then drop the local session and start a fresh anonymous one
    /// so the app returns to first-run rather than stranding on the loading
    /// spinner.
    func deleteAccount() async throws {
        guard let me = currentUserId else { return }
        try await client
            .rpc("delete_account", params: ["p_user": me.uuidString])
            .execute()
        log.info("Deleted account \(me)")
        try? await client.auth.signOut()
        currentUserId = nil
        isAnonymous = false
        bootstrapTask = nil
        await bootstrap()
    }
}
