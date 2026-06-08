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
    /// An invite code captured from a universal link before the user had a
    /// recoverable identity. Held until Apple Sign-In completes, then
    /// consumed in [[AppleSignInPairingGate]]. Without this, anonymous users
    /// could pair via deep link and lose their account forever on reinstall.
    var deferredInviteCode: String?
    /// Set when an invite link arrives for an anonymous user; observed by
    /// RootView to surface the sign-in-to-pair flow.
    var requiresSignInToPair = false

    private let inviteCodeLength = 6
    private let inviteCodeAlphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    // AASA is served at https://jackwallner.com/.well-known/apple-app-site-association
    // (matching `/pair/*`); bond.jackwallner.com has no DNS and never served one,
    // so invite links built against it silently failed to deep-link. This host
    // drives both invite-URL generation and incoming-link matching below.
    private let universalLinkHost = "jackwallner.com"

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
        lastError = nil
        do {
            try await callCreateSoloCouple(me)
            await loadCouple()
        } catch {
            // A stale PostgREST schema cache (function exists in Postgres but
            // the gateway hasn't reloaded) presents as a transient PGRST202.
            // Retry once after a beat before giving up.
            if isSchemaCacheError(error) {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                do {
                    try await callCreateSoloCouple(me)
                    await loadCouple()
                    lastError = nil
                    return
                } catch {
                    log.error("create_solo_couple retry failed: \(error.localizedDescription)")
                }
            } else {
                log.error("create_solo_couple failed: \(error.localizedDescription)")
            }
            // Human copy, not raw PostgREST jargon.
            lastError = "We couldn't finish setup. Please try again in a moment."
        }
    }

    private func callCreateSoloCouple(_ me: UUID) async throws {
        try await supabase.client
            .rpc("create_solo_couple", params: ["p_user": me.uuidString])
            .execute()
    }

    private func isSchemaCacheError(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        return text.contains("schema cache")
            || text.contains("pgrst202")
            || text.contains("could not find the function")
    }

    func generateInviteCode() async -> URL? {
        guard let me = supabase.currentUserId else {
            lastError = "Sign in first."
            return nil
        }
        lastError = nil
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
        lastError = nil
        defer { isPairing = false }
        do {
            try await supabase.client
                .rpc("consume_invite_code", params: ["p_code": code, "p_user": me.uuidString])
                .execute()
            lastError = nil
            await loadCouple()
            if coupleId != nil && !solo {
                justPaired = true
                // Onboarding prefs describe the partner from the user's
                // POV (private hints). Once paired, the real partner owns
                // their server-side love_language; nothing to push here.
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Unpairs the current couple. The `leave_couple` RPC splits the shared
    /// couple into two solo couples, re-homing each partner's own reminders,
    /// check-ins, and event history and copying shared milestones to both — so
    /// neither partner loses data.
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
        deferredInviteCode = nil
        requiresSignInToPair = false
    }

    func handleIncomingURL(_ url: URL) {
        guard let host = url.host, host == universalLinkHost || url.scheme == "bond" else { return }
        let parts = url.pathComponents
        guard let pairIndex = parts.firstIndex(of: "pair"),
              pairIndex + 1 < parts.count else { return }
        let code = parts[pairIndex + 1]
        // Anonymous users cannot pair via deep link without first establishing
        // a recoverable identity, otherwise the partner ends up linked to a
        // throwaway account that vanishes on reinstall. Defer until the gate
        // upgrades them via Apple Sign-In.
        if supabase.isAnonymous {
            deferredInviteCode = code
            requiresSignInToPair = true
            return
        }
        Task { await consumeInviteCode(code) }
    }

    /// Consume an invite code captured before the user had a recoverable
    /// identity. Called by [[AppleSignInPairingGate]] after sign-in succeeds.
    func consumeDeferredInviteIfNeeded() async {
        guard let code = deferredInviteCode else { return }
        deferredInviteCode = nil
        requiresSignInToPair = false
        await consumeInviteCode(code)
    }
}
