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
    /// `signInAnonymously()` independently and create two anon users — the
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

    /// Restore a cached session, or silently start an anonymous one so every
    /// user has a backing Supabase identity without seeing a sign-in screen.
    /// Apple Sign-In is reserved for opt-in upgrades (pairing, account
    /// recovery), not for first launch.
    func restoreSession() async {
        do {
            let session = try await client.auth.session
            currentUserId = session.user.id
            isAnonymous = session.user.isAnonymous
            log.info("Session restored for user \(session.user.id) (anon: \(self.isAnonymous))")
        } catch {
            log.notice("No cached session — signing in anonymously")
            await signInAnonymously()
        }
    }

    func signInAnonymously() async {
        do {
            let session = try await client.auth.signInAnonymously()
            currentUserId = session.user.id
            isAnonymous = true
            log.info("Signed in anonymously — user \(session.user.id)")
        } catch {
            // Don't nuke an already-restored session on failure: restoreSession()
            // and this method can race at launch, and clearing currentUserId here
            // would leave the user stuck on the loading screen even though a valid
            // session existed.
            log.error("Anonymous sign-in failed: \(error.localizedDescription)")
        }
    }

    func signInWithApple(idToken: String, nonce: String) async throws {
        // When the user is already in an anonymous session, link the Apple
        // identity to *that* user rather than minting a new one. Without
        // this branch, every "upgrade your account" flow silently swapped
        // auth.uid() and orphaned the user's reminders, milestones, and
        // couple row to the abandoned anon identity.
        let credentials = OpenIDConnectCredentials(
            provider: .apple, idToken: idToken, nonce: nonce
        )
        let session: Session
        if isAnonymous {
            do {
                session = try await client.auth.linkIdentityWithIdToken(credentials: credentials)
                log.info("Linked Apple identity to anonymous user \(session.user.id)")
            } catch {
                // If linking fails because the Apple identity is *already*
                // attached to a different Supabase user (e.g. user previously
                // signed in with Apple on another device), fall back to a
                // straight sign-in so they can recover that account. Their
                // anonymous-session data is lost in that case, which is the
                // correct tradeoff — the recoverable account wins.
                log.notice("linkIdentityWithIdToken failed (\(error.localizedDescription)); falling back to signInWithIdToken")
                session = try await client.auth.signInWithIdToken(credentials: credentials)
            }
        } else {
            session = try await client.auth.signInWithIdToken(credentials: credentials)
        }
        currentUserId = session.user.id
        isAnonymous = session.user.isAnonymous
        log.info("Signed in with Apple — user \(session.user.id)")
    }

    func signOut() async {
        try? await client.auth.signOut()
        currentUserId = nil
        isAnonymous = false
        bootstrapTask = nil
        log.info("Signed out")
        // Immediately establish a fresh anonymous session so the router
        // doesn't strand the user on the loading spinner. Sign-out is a
        // "new guest session" event, not a terminal state — without this,
        // `RootView` keeps rendering `.loading` because nothing else
        // re-runs `bootstrap()`.
        await bootstrap()
    }
}
