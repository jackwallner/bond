import Foundation
import Testing

@testable import Bond

struct CoupleDTOTests {
    private let partnerA = UUID()
    private let partnerB = UUID()
    private let stranger = UUID()

    @Test func partnerId_selfIsA_returnsB() {
        let c = CoupleDTO(id: UUID(), partnerA: partnerA, partnerB: partnerB, pairedAt: nil, solo: false)
        #expect(c.partnerId(forSelf: partnerA) == partnerB)
    }

    @Test func partnerId_selfIsB_returnsA() {
        let c = CoupleDTO(id: UUID(), partnerA: partnerA, partnerB: partnerB, pairedAt: nil, solo: false)
        #expect(c.partnerId(forSelf: partnerB) == partnerA)
    }

    @Test func partnerId_stranger_returnsNil() {
        let c = CoupleDTO(id: UUID(), partnerA: partnerA, partnerB: partnerB, pairedAt: nil, solo: false)
        #expect(c.partnerId(forSelf: stranger) == nil)
    }

    @Test func partnerId_solo_sameUser() {
        let me = UUID()
        let c = CoupleDTO(id: UUID(), partnerA: me, partnerB: me, pairedAt: nil, solo: true)
        #expect(c.partnerId(forSelf: me) == me)
    }

    @Test func codable_roundTrip() throws {
        let original = CoupleDTO(id: UUID(), partnerA: partnerA, partnerB: partnerB, pairedAt: .now, solo: false)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CoupleDTO.self, from: data)
        #expect(decoded == original)
    }
}


/// Launch routing. A returning user whose couple lookup threw (no signal, a
/// server hiccup) has a couple that simply isn't known yet. Treating that as
/// "no couple" sends them through first-run onboarding, where finishing fails
/// with "already in a couple".
struct RootDestinationTests {
    private func resolve(
        isBootstrapped: Bool = true,
        isAuthenticated: Bool = true,
        hasCouple: Bool = false,
        coupleLookupFailed: Bool = false,
        hasDeferredInvite: Bool = false,
        justPaired: Bool = false,
        isSolo: Bool = false,
        hasCapturedIntake: Bool = false
    ) -> RootDestination {
        RootDestination.resolve(
            isBootstrapped: isBootstrapped,
            isAuthenticated: isAuthenticated,
            hasCouple: hasCouple,
            coupleLookupFailed: coupleLookupFailed,
            hasDeferredInvite: hasDeferredInvite,
            justPaired: justPaired,
            isSolo: isSolo,
            hasCapturedIntake: hasCapturedIntake
        )
    }

    @Test func returningUser_whoseCoupleLookupFailed_waitsInsteadOfRestartingOnboarding() {
        #expect(resolve(coupleLookupFailed: true) == .loading)
    }

    @Test func inviteLinkUser_whoseCoupleLookupFailed_alsoWaits() {
        #expect(resolve(coupleLookupFailed: true, hasDeferredInvite: true) == .loading)
    }

    @Test func newUser_whoseLookupFoundNoCouple_startsOnboarding() {
        #expect(resolve() == .intentSetup)
    }

    @Test func inviteLinkUser_whoseLookupFoundNoCouple_seesTheInviteWelcome() {
        #expect(resolve(hasDeferredInvite: true) == .inviteWelcome)
    }

    @Test func knownCouple_isNotHeldBackByALaterFailedLookup() {
        #expect(resolve(hasCouple: true, coupleLookupFailed: true, isSolo: true) == .home)
    }

    @Test func nothingResolvesBeforeBootstrapOrSignIn() {
        #expect(resolve(isBootstrapped: false, hasCouple: true) == .loading)
        #expect(resolve(isAuthenticated: false, hasCouple: true) == .loading)
    }

    @Test func pairedUserWithoutIntake_getsTheInviteeIntake() {
        #expect(resolve(hasCouple: true, isSolo: false, hasCapturedIntake: false) == .inviteeIntake)
        #expect(resolve(hasCouple: true, isSolo: false, hasCapturedIntake: true) == .home)
    }

    @Test func justPaired_showsTheSuccessScreenFirst() {
        #expect(resolve(hasCouple: true, justPaired: true) == .pairingSuccess)
    }
}

@MainActor
@Suite(.serialized)
struct CoupleLookupTests {
    private let me = UUID()

    /// `loadCouple()` reads the signed-in user from the shared session holder.
    private func signedIn(_ body: () async -> Void) async {
        let session = SupabaseService.shared
        let before = session.currentUserId
        session.currentUserId = me
        await body()
        session.currentUserId = before
    }

    @Test func failedLookup_isRecorded_andKeepsWhatWasKnown() async {
        let known = UUID()
        let mine = me
        await signedIn {
            let pairing = PairingService()
            pairing.fetchCouples = { _ in
                [CoupleDTO(id: known, partnerA: mine, partnerB: mine, pairedAt: nil, solo: true)]
            }
            await pairing.loadCouple()
            #expect(pairing.coupleId == known)
            #expect(pairing.lastLoadFailed == false)

            pairing.fetchCouples = { _ in throw URLError(.notConnectedToInternet) }
            await pairing.loadCouple()
            #expect(pairing.lastLoadFailed)
            #expect(pairing.coupleId == known)
        }
    }

    @Test func lookupThatFindsNoCouple_isNotAFailure() async {
        await signedIn {
            let pairing = PairingService()
            pairing.fetchCouples = { _ in [] }
            await pairing.loadCouple()
            #expect(pairing.coupleId == nil)
            #expect(pairing.lastLoadFailed == false)
        }
    }

    @Test func firstLookupThatThrows_leavesNoCoupleAndFlagsIt() async {
        await signedIn {
            let pairing = PairingService()
            pairing.fetchCouples = { _ in throw URLError(.timedOut) }
            await pairing.loadCouple()
            #expect(pairing.coupleId == nil)
            #expect(pairing.lastLoadFailed)
        }
    }
}
