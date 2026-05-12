import Foundation
import Supabase

@MainActor
@Observable
final class PairingService {
    private let supabase = SupabaseService.shared

    var coupleId: UUID?
    var partnerProfile: ProfileDTO?
    var pendingInviteCode: String?
    var lastError: String?

    private let inviteCodeLength = 6
    private let inviteCodeAlphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
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
            if let partnerUUID = row?.partnerId(forSelf: me) {
                partnerProfile = try await supabase.client
                    .from("profiles")
                    .select()
                    .eq("id", value: partnerUUID.uuidString)
                    .single()
                    .execute()
                    .value
            }
        } catch {
            // No couple yet — expected for new users.
            coupleId = nil
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

        let payload: [String: AnyJSON] = [
            "code": .string(code),
            "created_by": .string(me.uuidString),
            "expires_at": .string(ISO8601DateFormatter().string(
                from: Date().addingTimeInterval(60 * 60 * 24)
            ))
        ]
        do {
            try await supabase.client
                .from("invite_codes")
                .insert(payload)
                .execute()
            pendingInviteCode = code
            return URL(string: "https://\(universalLinkHost)/pair/\(code)")
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
        do {
            try await supabase.client
                .rpc("consume_invite_code", params: ["p_code": code, "p_user": me.uuidString])
                .execute()
            await loadCouple()
        } catch {
            lastError = error.localizedDescription
        }
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
