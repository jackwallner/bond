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
    var isAuthenticated: Bool { currentUserId != nil }

    private init() {
        self.client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey
        )
        Task { await restoreSession() }
    }

    func restoreSession() async {
        do {
            let session = try await client.auth.session
            currentUserId = session.user.id
            log.info("Session restored for user \(session.user.id)")
        } catch {
            currentUserId = nil
            log.notice("No cached session found: \(error.localizedDescription)")
        }
    }

    func signInWithApple(idToken: String, nonce: String) async throws {
        let session = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )
        currentUserId = session.user.id
        log.info("Signed in with Apple — user \(session.user.id)")
    }

    func signOut() async {
        try? await client.auth.signOut()
        currentUserId = nil
        log.info("Signed out")
    }
}
