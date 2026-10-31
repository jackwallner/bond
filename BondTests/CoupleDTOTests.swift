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

    // The app re-reads what moves with a couple (the reminders it arms, the
    // milestones) when a lookup finds the relationship changed. Unpairing is the
    // case that matters: the partner's reminders must stop firing at once.

    @Test func unpairing_asTheInviter_keepsTheCoupleId_butStillTellsTheApp() async {
        let couple = UUID()
        let mine = me
        await signedIn {
            let pairing = PairingService()
            pairing.coupleId = couple
            pairing.solo = false
            var told = 0
            pairing.onRelationshipChange = { told += 1 }
            // The inviter's row is repurposed in place as their solo couple.
            pairing.fetchCouples = { _ in
                [CoupleDTO(id: couple, partnerA: mine, partnerB: mine, pairedAt: nil, solo: true)]
            }

            await pairing.loadCouple()

            #expect(pairing.solo)
            #expect(told == 1)
        }
    }

    @Test func unpairing_asTheOtherPartner_movesToANewCouple_andTellsTheApp() async {
        let mine = me
        await signedIn {
            let pairing = PairingService()
            pairing.coupleId = UUID()
            pairing.solo = false
            var told = 0
            pairing.onRelationshipChange = { told += 1 }
            pairing.fetchCouples = { _ in
                [CoupleDTO(id: UUID(), partnerA: mine, partnerB: mine, pairedAt: nil, solo: true)]
            }

            await pairing.loadCouple()

            #expect(told == 1)
        }
    }

    @Test func firstLookup_isNotARelationshipChange() async {
        let mine = me
        await signedIn {
            let pairing = PairingService()
            var told = 0
            pairing.onRelationshipChange = { told += 1 }
            pairing.fetchCouples = { _ in
                [CoupleDTO(id: UUID(), partnerA: mine, partnerB: mine, pairedAt: nil, solo: true)]
            }

            await pairing.loadCouple()

            #expect(told == 0)
        }
    }

    @Test func lookupThatFindsTheSameRelationship_staysQuiet() async {
        let couple = UUID()
        let mine = me
        await signedIn {
            let pairing = PairingService()
            pairing.coupleId = couple
            pairing.solo = true
            var told = 0
            pairing.onRelationshipChange = { told += 1 }
            pairing.fetchCouples = { _ in
                [CoupleDTO(id: couple, partnerA: mine, partnerB: mine, pairedAt: nil, solo: true)]
            }

            await pairing.loadCouple()
            await pairing.loadCouple()

            #expect(told == 0)
        }
    }

    @Test func lookupThatFails_isNotARelationshipChange() async {
        await signedIn {
            let pairing = PairingService()
            pairing.coupleId = UUID()
            pairing.solo = false
            var told = 0
            pairing.onRelationshipChange = { told += 1 }
            pairing.fetchCouples = { _ in throw URLError(.notConnectedToInternet) }

            await pairing.loadCouple()

            #expect(told == 0)
        }
    }
}

/// The stored session is the only handle on an anonymous account. A launch whose
/// restore failed because a request never completed must not swap it for a brand
/// new anonymous user: the new session replaces the stored one, and everything
/// the first user made (couple, reminders, milestones) is unreachable from then on.
@MainActor
@Suite(.serialized)
struct SessionRestoreTests {
    private struct NoStoredSession: Error {}

    /// Runs `restoreSession` against the shared holder and puts it back as found.
    private func restore(
        loading load: () async throws -> SupabaseService.RestoredIdentity
    ) async -> (freshSessions: Int, userId: UUID?) {
        let service = SupabaseService.shared
        let before = (service.currentUserId, service.isAnonymous)
        service.currentUserId = nil
        var freshSessions = 0
        await service.restoreSession(loadSession: load, startFreshSession: { freshSessions += 1 })
        let userId = service.currentUserId
        service.currentUserId = before.0
        service.isAnonymous = before.1
        return (freshSessions, userId)
    }

    @Test func storedSession_isKept_andNobodyNewIsStarted() async {
        let stored = UUID()
        let result = await restore { SupabaseService.RestoredIdentity(userId: stored, isAnonymous: true) }
        #expect(result.userId == stored)
        #expect(result.freshSessions == 0)
    }

    @Test func noStoredSession_startsAnAnonymousUser() async {
        let result = await restore { throw NoStoredSession() }
        #expect(result.freshSessions == 1)
    }

    @Test func requestThatNeverCompletes_doesNotStartANewUser() async {
        let failures: [URLError.Code] = [.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost]
        for code in failures {
            let result = await restore { throw URLError(code) }
            #expect(result.freshSessions == 0, "a \(code) must not mint a new user")
            #expect(result.userId == nil)
        }
    }
}

/// Upgrading an anonymous account to Apple links the identity to that user, so the
/// couple and reminders come along. Only an identity that already belongs to someone
/// else is signed in as that someone; a link that failed because a request never
/// completed says nothing about it, and signing in then mints a new, empty account
/// while the real one is orphaned.
@MainActor
@Suite(.serialized)
struct AppleSignInTests {
    private struct IdentityBelongsToSomeoneElse: Error {}

    /// Runs `signInWithApple` against the shared holder and puts it back as found.
    private func signIn(
        asAnonymous anonymous: Bool,
        link: () async throws -> SupabaseService.RestoredIdentity,
        signIn: () async throws -> SupabaseService.RestoredIdentity
    ) async -> (user: UUID?, thrown: Error?) {
        let service = SupabaseService.shared
        let before = (service.currentUserId, service.isAnonymous)
        service.isAnonymous = anonymous
        var thrown: Error?
        do { try await service.signInWithApple(link: link, signIn: signIn) } catch { thrown = error }
        let user = service.currentUserId
        service.currentUserId = before.0
        service.isAnonymous = before.1
        return (user, thrown)
    }

    @Test func aLinkThatWorks_keepsTheUsersOwnId_andSignsNobodyIn() async {
        let mine = UUID()
        var signIns = 0
        let result = await signIn(
            asAnonymous: true,
            link: { SupabaseService.RestoredIdentity(userId: mine, isAnonymous: false) },
            signIn: { signIns += 1; return SupabaseService.RestoredIdentity(userId: UUID(), isAnonymous: false) }
        )
        #expect(result.user == mine)
        #expect(signIns == 0)
    }

    @Test func anIdentityThatBelongsToSomeoneElse_signsInAsThem() async {
        let recovered = UUID()
        let result = await signIn(
            asAnonymous: true,
            link: { throw IdentityBelongsToSomeoneElse() },
            signIn: { SupabaseService.RestoredIdentity(userId: recovered, isAnonymous: false) }
        )
        #expect(result.user == recovered)
        #expect(result.thrown == nil)
    }

    @Test func aLinkThatLostItsConnection_isNotRetriedAsASignIn() async {
        let failures: [URLError.Code] = [.networkConnectionLost, .timedOut, .notConnectedToInternet, .cannotConnectToHost]
        for code in failures {
            var signIns = 0
            let result = await signIn(
                asAnonymous: true,
                link: { throw URLError(code) },
                signIn: { signIns += 1; return SupabaseService.RestoredIdentity(userId: UUID(), isAnonymous: false) }
            )
            #expect(signIns == 0, "a \(code) must not mint a new account")
            #expect(result.user == nil)
            #expect(result.thrown is URLError)
        }
    }

    @Test func aUserWhoIsNotAnonymous_signsInDirectly() async {
        let someone = UUID()
        var links = 0
        let result = await signIn(
            asAnonymous: false,
            link: { links += 1; return SupabaseService.RestoredIdentity(userId: UUID(), isAnonymous: false) },
            signIn: { SupabaseService.RestoredIdentity(userId: someone, isAnonymous: false) }
        )
        #expect(result.user == someone)
        #expect(links == 0)
    }
}
