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
            // No `.single()`: zero rows must be distinguishable from a failed
            // request. With `.single()` both threw, and the catch below wiped
            // coupleId — so one flaky request on launch dumped an existing
            // (even paired) user back into intent setup, where the solo-couple
            // RPC then failed with "already in a couple".
            let rows: [CoupleDTO] = try await supabase.client
                .from("couples")
                .select()
                .or("partner_a.eq.\(me.uuidString),partner_b.eq.\(me.uuidString)")
                .limit(1)
                .execute()
                .value
            let row = rows.first
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
                // An invitee who paired during onboarding never typed a
                // partner name — seed it from the partner's profile so
                // prompts and headers don't address "them".
                let prefs = OnboardingPreferences.shared
                if prefs.partnerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let name = partnerProfile?.displayName,
                   !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    prefs.partnerName = name
                }
            } else {
                partnerProfile = nil
            }
            log.info("Loaded couple \(self.coupleId?.uuidString ?? "nil") (solo: \(self.solo))")
        } catch {
            // Transport/auth failure — keep whatever state we had rather than
            // pretending the user has no couple.
            log.error("loadCouple failed (state kept): \(error.localizedDescription)")
        }
    }

    /// Polls while the inviter sits on the "share this code" screen. Nothing
    /// notifies this device when the partner consumes the code on theirs —
    /// without polling, the inviter stays "solo" until an app restart and the
    /// pairing looks broken. Returns when paired, when the task is cancelled
    /// (view dismissed), or when the invite expires.
    func waitForPartnerToPair() async {
        while !Task.isCancelled {
            guard pendingInviteCode != nil else { return }
            if let expiry = pendingInviteExpiresAt, expiry < .now { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await loadCouple()
            if coupleId != nil && !solo {
                pendingInviteCode = nil
                pendingInviteURL = nil
                pendingInviteExpiresAt = nil
                justPaired = true
                return
            }
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
        // Best-effort: retire any earlier codes from this user so only the
        // most recently shared one works and stale rows don't accumulate.
        _ = try? await supabase.client
            .from("invite_codes")
            .delete()
            .eq("created_by", value: me.uuidString)
            .execute()
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
            lastError = Self.friendlyPairingError(error)
        }
    }

    /// The pairing RPC raises terse Postgres exceptions ("invalid or expired
    /// code") that PostgREST passes through verbatim — translate the known
    /// ones into copy a person on the pairing screen can act on.
    private static func friendlyPairingError(_ error: Error) -> String {
        let text = error.localizedDescription.lowercased()
        if text.contains("invalid or expired code") {
            return "That code didn't work — it may have expired. Ask your partner for a fresh one."
        }
        if text.contains("cannot pair with yourself") {
            return "That's your own code. Share it with your partner and enter theirs here."
        }
        if text.contains("you are already in a couple") {
            return "You're already paired. Unpair in Settings before using a new code."
        }
        if text.contains("inviter already in a couple") {
            return "Whoever shared that code is already paired with someone."
        }
        return "Pairing didn't work. Check the code and try again."
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
        let isUniversalLink = url.host == universalLinkHost
        let isCustomScheme = url.scheme == "bond"
        guard isUniversalLink || isCustomScheme else { return }
        // In bond://pair/CODE the "pair" segment is the URL *host*, not a
        // path component — fold it back in so both link forms parse the same.
        var parts = url.pathComponents.filter { $0 != "/" }
        if isCustomScheme, let host = url.host {
            parts.insert(host, at: 0)
        }
        guard let pairIndex = parts.firstIndex(of: "pair"),
              pairIndex + 1 < parts.count else { return }
        let code = parts[pairIndex + 1].uppercased()
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
    /// The code is only cleared once pairing actually succeeds — clearing it
    /// up front meant one failed RPC silently dropped the invite, and the
    /// invitee onboarding flow (which exists while the code does) vanished
    /// out from under the user with no way to retry.
    func consumeDeferredInviteIfNeeded() async {
        guard let code = deferredInviteCode else { return }
        requiresSignInToPair = false
        await consumeInviteCode(code)
        if coupleId != nil && !solo {
            deferredInviteCode = nil
        }
    }
}
