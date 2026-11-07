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
    /// The holder starts signed out: the app that hosts the tests has usually
    /// signed in anonymously by now, and a link that failed leaves that user in place.
    private func signIn(
        asAnonymous anonymous: Bool,
        link: () async throws -> SupabaseService.RestoredIdentity,
        signIn: () async throws -> SupabaseService.RestoredIdentity
    ) async -> (user: UUID?, thrown: Error?) {
        let service = SupabaseService.shared
        let before = (service.currentUserId, service.isAnonymous)
        service.currentUserId = nil
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

// MARK: - State machine audit 2026-11-06: B13 (sm4) and B11, who and what the app is on

@MainActor
@Suite(.serialized)
struct IdentityAndCoupleStateTests {
    private let me = UUID()
    private let partner = UUID()

    private func signedIn(_ body: () async -> Void) async {
        let session = SupabaseService.shared
        let before = session.currentUserId
        session.currentUserId = me
        await body()
        session.currentUserId = before
    }

    @Test func b13_control_aFailedCouplesRequestChangesNothing() async {
        await signedIn {
            let old = UUID()
            let pairing = PairingService()
            pairing.coupleId = old
            pairing.solo = true
            var told = 0
            pairing.onRelationshipChange = { told += 1 }
            pairing.fetchCouples = { _ in throw URLError(.notConnectedToInternet) }
            await pairing.loadCouple()
            #expect(pairing.lastLoadFailed)
            #expect(pairing.coupleId == old && pairing.solo && told == 0)
        }
    }

    @Test func b13_aLookupWhoseProfileRequestFailsKeepsWhatWasKnown() async {
        let mine = me, theirs = partner
        await signedIn {
            let old = UUID()
            let newCouple = UUID()
            let pairing = PairingService()
            pairing.coupleId = old
            pairing.solo = true
            var told = 0
            pairing.onRelationshipChange = { told += 1 }
            // The couples request works; the partner-profile request that follows does not.
            pairing.fetchCouples = { _ in
                [CoupleDTO(id: newCouple, partnerA: mine, partnerB: theirs, pairedAt: nil, solo: false)]
            }
            pairing.fetchProfile = { _ in throw URLError(.networkConnectionLost) }

            await pairing.loadCouple()

            #expect(pairing.lastLoadFailed)
            #expect(pairing.coupleId == old && pairing.solo,
                    "paired with no partner profile: coupleId=\(String(describing: pairing.coupleId)) solo=\(pairing.solo)")
            #expect(told == 0, "a failed lookup announced a relationship change")
        }
    }

    @Test func b13_control_aLookupWithItsProfileCommitsTheWholeCouple() async {
        let mine = me, theirs = partner
        await signedIn {
            let newCouple = UUID()
            let pairing = PairingService()
            pairing.coupleId = UUID()
            pairing.solo = true
            var told = 0
            pairing.onRelationshipChange = { told += 1 }
            pairing.fetchCouples = { _ in
                [CoupleDTO(id: newCouple, partnerA: mine, partnerB: theirs, pairedAt: nil, solo: false)]
            }
            pairing.fetchProfile = { id in ProfileDTO(id: id, displayName: "") }

            await pairing.loadCouple()

            #expect(!pairing.lastLoadFailed)
            #expect(pairing.coupleId == newCouple && !pairing.solo)
            #expect(pairing.partnerProfile?.id == theirs)
            #expect(told == 1)
        }
    }

    private struct IdentityBelongsToSomeoneElse: Error {}

    @Test func b11_anAppleSignInThatRecoversAnotherAccountReloadsWhatTheAppIsOn() async throws {
        let service = SupabaseService.shared
        let before = (service.currentUserId, service.isAnonymous, service.onIdentityChange)
        defer {
            service.currentUserId = before.0
            service.isAnonymous = before.1
            service.onIdentityChange = before.2
        }
        let anonymous = UUID()
        let recovered = UUID()
        let recoveredCouple = UUID()
        service.currentUserId = anonymous
        service.isAnonymous = true

        // The app's handler, as BondApp wires it: look the couple up again.
        let pairing = PairingService()
        pairing.coupleId = UUID()
        pairing.solo = true
        var relationshipChanges = 0
        pairing.onRelationshipChange = { relationshipChanges += 1 }
        pairing.fetchCouples = { user in
            user == recovered
                ? [CoupleDTO(id: recoveredCouple, partnerA: recovered, partnerB: recovered, pairedAt: nil, solo: true)]
                : []
        }
        var told: [UUID] = []
        service.onIdentityChange = { user in
            told.append(user)
            await pairing.loadCouple()
        }

        try await service.signInWithApple(
            link: { throw IdentityBelongsToSomeoneElse() },
            signIn: { SupabaseService.RestoredIdentity(userId: recovered, isAnonymous: false) }
        )

        #expect(told == [recovered])
        #expect(pairing.coupleId == recoveredCouple, "the old anonymous couple stayed in memory")
        #expect(relationshipChanges == 1)
    }

    @Test func b11_control_aLinkThatKeepsTheSameUserReloadsNothing() async throws {
        let service = SupabaseService.shared
        let before = (service.currentUserId, service.isAnonymous, service.onIdentityChange)
        defer {
            service.currentUserId = before.0
            service.isAnonymous = before.1
            service.onIdentityChange = before.2
        }
        let mine = UUID()
        service.currentUserId = mine
        service.isAnonymous = true
        var told = 0
        service.onIdentityChange = { _ in told += 1 }

        try await service.signInWithApple(
            link: { SupabaseService.RestoredIdentity(userId: mine, isAnonymous: false) },
            signIn: { SupabaseService.RestoredIdentity(userId: UUID(), isAnonymous: false) }
        )

        #expect(told == 0)
    }
}

// MARK: - State machine review 2026-11-06: N1, the daily check-in question

struct DailyCheckInRuleTests {
    private let me = UUID()
    private let partner = UUID()
    private let couple = UUID()

    private func zone(_ id: String) -> TimeZone { TimeZone(identifier: id)! }

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0, in tz: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func calendar(_ tz: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal
    }

    private func answer(_ question: UUID, by user: UUID, at time: Date) -> QuestionResponseDTO {
        QuestionResponseDTO(id: UUID(), questionId: question, coupleId: couple, userId: user, response: "x", createdAt: time)
    }

    @Test func n1_theQuestionDoesNotChangeAtMidnightUTC() {
        let la = zone("America/Los_Angeles")
        // 4 PM in Los Angeles is midnight UTC.
        let before = DailyCheckInService.dayNumber(for: at(2026, 11, 6, 15, in: la), in: la)
        let after = DailyCheckInService.dayNumber(for: at(2026, 11, 6, 17, in: la), in: la)
        let nextMorning = DailyCheckInService.dayNumber(for: at(2026, 11, 7, 0, 30, in: la), in: la)
        #expect(before == after, "changed at 00:00 UTC")
        #expect(nextMorning == before + 1)
    }

    @Test func n1_whileTheDatesMatchTheDayIsTheOneTheStoreVersionUses() {
        // The store version counts the UTC date. At 10 AM in Los Angeles both dates are the 6th.
        let la = zone("America/Los_Angeles")
        let utc = zone("UTC")
        let morning = at(2026, 11, 6, 10, in: la)
        #expect(DailyCheckInService.dayNumber(for: morning, in: la) == DailyCheckInService.dayNumber(for: morning, in: utc))
    }

    @Test func n1_answersEitherSideOfMidnightStayOnOneQuestionAndBothSeeTheReveal() {
        let la = zone("America/Los_Angeles")
        let cal = calendar(la)
        let yesterdays = UUID(), todays = UUID()
        var answers = [answer(yesterdays, by: partner, at: at(2026, 11, 6, 23, 50, in: la))]

        // I open it ten minutes after midnight: the question my partner answered is mine to answer.
        let tenPast = at(2026, 11, 7, 0, 10, in: la)
        #expect(DailyCheckInService.currentQuestionId(dayQuestion: todays, responses: answers, me: me, now: tenPast, calendar: cal) == yesterdays)
        // My partner, meanwhile, waits on it rather than moving on.
        #expect(DailyCheckInService.currentQuestionId(dayQuestion: todays, responses: answers, me: partner, now: tenPast, calendar: cal) == yesterdays)

        answers.append(answer(yesterdays, by: me, at: tenPast))
        let later = at(2026, 11, 7, 8, in: la)
        // Both see the reveal for the rest of the day.
        #expect(DailyCheckInService.currentQuestionId(dayQuestion: todays, responses: answers, me: me, now: later, calendar: cal) == yesterdays)
        #expect(DailyCheckInService.currentQuestionId(dayQuestion: todays, responses: answers, me: partner, now: later, calendar: cal) == yesterdays)
        // The next day starts a new question.
        let nextDay = at(2026, 11, 8, 9, in: la)
        let tomorrows = UUID()
        #expect(DailyCheckInService.currentQuestionId(dayQuestion: tomorrows, responses: answers, me: me, now: nextDay, calendar: cal) == tomorrows)
    }

    @Test func n1_partnersInDifferentZonesAnswerTheSameQuestion() {
        let newYork = zone("America/New_York"), tokyo = zone("Asia/Tokyo")
        let tokyoQuestion = UUID(), newYorkQuestion = UUID()
        // 10 AM on the 7th in Tokyo is 8 PM on the 6th in New York.
        let tokyoMorning = at(2026, 11, 7, 10, in: tokyo)
        var answers = [answer(tokyoQuestion, by: partner, at: tokyoMorning)]
        let soon = tokyoMorning.addingTimeInterval(1_800)
        #expect(DailyCheckInService.currentQuestionId(
            dayQuestion: newYorkQuestion, responses: answers, me: me, now: soon, calendar: calendar(newYork)
        ) == tokyoQuestion)

        answers.append(answer(tokyoQuestion, by: me, at: soon))
        let after = soon.addingTimeInterval(600)
        #expect(DailyCheckInService.currentQuestionId(
            dayQuestion: newYorkQuestion, responses: answers, me: me, now: after, calendar: calendar(newYork)
        ) == tokyoQuestion)
        #expect(DailyCheckInService.currentQuestionId(
            dayQuestion: tokyoQuestion, responses: answers, me: partner, now: after, calendar: calendar(tokyo)
        ) == tokyoQuestion)
    }

    @Test func n1_aPartnerOnTheStoreVersionStillGetsAnAnswerToTheirQuestion() {
        // The store version moved to its next question at 4 PM in Los Angeles and my partner answered it.
        let la = zone("America/Los_Angeles")
        let storeQuestion = UUID(), myDayQuestion = UUID()
        let answers = [answer(storeQuestion, by: partner, at: at(2026, 11, 6, 16, 30, in: la))]
        #expect(DailyCheckInService.currentQuestionId(
            dayQuestion: myDayQuestion, responses: answers, me: me, now: at(2026, 11, 6, 19, in: la), calendar: calendar(la)
        ) == storeQuestion)
    }

    @Test func n1_control_aQuestionNobodyAnsweredIsTheDaysQuestion_andAnUnansweredOneExpiresAfterADay() {
        let la = zone("America/Los_Angeles")
        let day = UUID(), stale = UUID()
        let now = at(2026, 11, 7, 12, in: la)
        #expect(DailyCheckInService.currentQuestionId(dayQuestion: day, responses: [], me: me, now: now, calendar: calendar(la)) == day)
        let old = [answer(stale, by: partner, at: now.addingTimeInterval(-25 * 3_600))]
        #expect(DailyCheckInService.currentQuestionId(dayQuestion: day, responses: old, me: me, now: now, calendar: calendar(la)) == day)
    }
}
