import Foundation
import OSLog
import Supabase

@MainActor
@Observable
final class PairingService {
    private let supabase = SupabaseService.shared
    private let log = Logger(subsystem: "com.jackwallner.bond", category: "pairing")

    var coupleId: UUID?
    var partnerProfile: ProfileDTO?
    var solo: Bool = false
    var pendingInviteCode: String?
    var pendingInviteURL: URL?
    var pendingInviteExpiresAt: Date?
    var isPairing = false
    /// Set when this device just completed pairing via an invite code, so the
    /// router can show the one-time success interstitial.
    var justPaired = false
    var lastError: String?

    private let inviteCodeLength = 6
    private let inviteCodeAlphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    private let universalLinkHost = "bond.jackwallner.com"

    func loadCouple() async {
        guard let me = supabase.currentUserId else { return }
        do {
            let row: CoupleDTO? = try await supabase.client
                .from("couples")
                .select()
                .or("partner_a.eq.\(me.uuidString),partner_b.eq.\(me.uuidString)")
                .limit(1)
                .single()
                .execute()
                .value
            coupleId = row?.id
            solo = row?.solo ?? false
            if let partnerUUID = row?.partnerId(forSelf: me), partnerUUID != me {
                partnerProfile = try await supabase.client
                    .from("profiles")
                    .select()
                    .eq("id", value: partnerUUID.uuidString)
                    .single()
                    .execute()
                    .value
            } else {
                partnerProfile = nil
            }
            log.info("Loaded couple \(self.coupleId?.uuidString ?? "nil") (solo: \(self.solo))")
        } catch {
            coupleId = nil
            solo = false
            log.notice("No couple found — new account: \(error.localizedDescription)")
        }
    }

    func createSoloCouple() async {
        guard let me = supabase.currentUserId else {
            lastError = "Sign in first."
            return
        }
        do {
            try await supabase.client
                .rpc("create_solo_couple", params: ["p_user": me.uuidString])
                .execute()
            await loadCouple()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func generateInviteCode() async -> URL? {
        guard let me = supabase.currentUserId else {
            lastError = "Sign in first."
            return nil
        }
        let code = (0..<inviteCodeLength)
            .map { _ in inviteCodeAlphabet.randomElement()! }
            .reduce(into: "") { $0.append($1) }

        let expiresAt = Date().addingTimeInterval(60 * 60 * 24)
        let payload: [String: AnyJSON] = [
            "code": .string(code),
            "created_by": .string(me.uuidString),
            "expires_at": .string(ISO8601DateFormatter().string(from: expiresAt))
        ]
        do {
            try await supabase.client
                .from("invite_codes")
                .insert(payload)
                .execute()
            let url = URL(string: "https://\(universalLinkHost)/pair/\(code)")
            pendingInviteCode = code
            pendingInviteURL = url
            pendingInviteExpiresAt = expiresAt
            lastError = nil
            return url
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func consumeInviteCode(_ code: String) async {
        guard let me = supabase.currentUserId else {
            lastError = "Sign in first."
            return
        }
        isPairing = true
        defer { isPairing = false }
        do {
            try await supabase.client
                .rpc("consume_invite_code", params: ["p_code": code, "p_user": me.uuidString])
                .execute()
            lastError = nil
            await loadCouple()
            if coupleId != nil && !solo {
                justPaired = true
                // Preferences are device-local until the user actually pairs;
                // a partner makes love language relevant server-side.
                await syncLoveLanguageToProfile()
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Pushes the on-device primary love language to the server profile so a
    /// paired partner's app can read it. No-op until the user has paired.
    private func syncLoveLanguageToProfile() async {
        guard let me = supabase.currentUserId else { return }
        let language = OnboardingPreferences.shared.primaryLoveLanguage.rawValue
        do {
            try await supabase.client
                .from("profiles")
                .update(["love_language": language])
                .eq("id", value: me.uuidString)
                .execute()
        } catch {
            log.notice("Love language sync failed: \(error.localizedDescription)")
        }
    }

    /// Leaves the current couple. Each partner keeps their own reminders;
    /// the couple row is dissolved server-side by the `leave_couple` RPC.
    func leaveCouple() async {
        guard let me = supabase.currentUserId else {
            lastError = "Sign in first."
            return
        }
        do {
            try await supabase.client
                .rpc("leave_couple", params: ["p_user": me.uuidString])
                .execute()
            lastError = nil
            await loadCouple()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Clears all in-memory pairing state on sign-out so the next account
    /// starts clean.
    func reset() {
        coupleId = nil
        partnerProfile = nil
        solo = false
        pendingInviteCode = nil
        pendingInviteURL = nil
        pendingInviteExpiresAt = nil
        justPaired = false
        isPairing = false
        lastError = nil
    }

    func handleIncomingURL(_ url: URL) {
        guard let host = url.host, host == universalLinkHost || url.scheme == "bond" else { return }
        let parts = url.pathComponents
        guard let pairIndex = parts.firstIndex(of: "pair"),
              pairIndex + 1 < parts.count else { return }
        let code = parts[pairIndex + 1]
        Task { await consumeInviteCode(code) }
    }
}
