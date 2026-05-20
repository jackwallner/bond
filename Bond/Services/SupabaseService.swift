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

    private init() {
        self.client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey
        )
        Task { await restoreSession() }
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
        let session = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )
        currentUserId = session.user.id
        isAnonymous = session.user.isAnonymous
        log.info("Signed in with Apple — user \(session.user.id)")
    }

    func signOut() async {
        try? await client.auth.signOut()
        currentUserId = nil
        isAnonymous = false
        log.info("Signed out")
    }
}
