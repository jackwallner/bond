import Foundation
import Testing
import UserNotifications

@testable import Bond

@MainActor
struct PartnerDeliveryTests {
    private let me = UUID()
    private let partner = UUID()

    private func reminder(author: UUID, target: UUID, type: String = "one_time") -> ReminderDTO {
        ReminderDTO(
            id: UUID(), coupleId: UUID(), authorId: author, targetId: target,
            title: "Flowers", body: nil, loveLanguage: .gifts, triggerType: type,
            fireAt: Date(timeIntervalSince1970: 2_000_000_000), rrule: nil, geofence: nil,
            windowStart: nil, windowEnd: nil, status: "scheduled",
            surpriseHiddenFromPartner: false, createdAt: nil
        )
    }

    @Test func withoutServerDeliveryEverythingForMeArmsLocally() {
        let arms = NotificationScheduler.armsLocally
        #expect(arms(reminder(author: me, target: me), me, false))
        #expect(arms(reminder(author: partner, target: me), me, false))
        #expect(!arms(reminder(author: me, target: partner), me, false))
    }

    @Test func serverDeliveryTakesOverOnlyWhatThePartnerWroteWithATime() {
        let arms = NotificationScheduler.armsLocally
        #expect(arms(reminder(author: me, target: me), me, true))
        #expect(!arms(reminder(author: partner, target: me), me, true))
        #expect(arms(reminder(author: partner, target: me, type: "location"), me, true))
        #expect(!arms(reminder(author: me, target: partner), me, true))
    }

    @Test func aPartnersReminderIsRescheduledNotUpserted() async throws {
        let repo = ReminderRepository(pairing: PairingService())
        repo.currentUserId = { [me] in me }
        var moved: [UUID] = []
        repo.rescheduleRow = { moved.append($0.id) }
        let row = reminder(author: partner, target: me)
        try await repo.upsert(row)
        #expect(moved == [row.id])
    }

    @Test func rescheduleSendsEveryArgumentEvenWhenCleared() throws {
        let data = try JSONEncoder().encode(RescheduleReminderParams(reminder(author: partner, target: me)))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(json.keys) == [
            "p_id", "p_trigger_type", "p_fire_at", "p_rrule", "p_geofence", "p_window_start", "p_window_end"
        ])
        #expect(json["p_rrule"] is NSNull)
    }
}

// MARK: - State machine audit 2026-11-06: B15 (sm3), one week on the phone and the server

struct WeekStartTests {
    private func pacific(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func calendar(firstWeekday: Int) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        cal.firstWeekday = firstWeekday
        cal.minimumDaysInFirstWeek = 1
        return cal
    }

    private func body(_ registration: PushRegistration) throws -> [String: Any] {
        let data = try JSONEncoder().encode(registration)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    @Test func b15_theServerIsToldTheWeekThePhoneCountsDoneFrom() throws {
        // en_US: the week starts on Sunday, so a weekly reminder done on Saturday
        // is open again on Sunday on the phone. The server (0017 reminder_done_at)
        // starts the week at the first weekday it was sent.
        let sundayFirst = calendar(firstWeekday: 1)
        let weekly = ReminderDTO(
            id: UUID(), coupleId: UUID(), authorId: UUID(), targetId: UUID(),
            title: "Date night", body: nil, loveLanguage: .time, triggerType: "recurring",
            fireAt: pacific(2026, 11, 1, 9), rrule: "FREQ=WEEKLY", geofence: nil,
            windowStart: nil, windowEnd: nil, status: "scheduled",
            surpriseHiddenFromPartner: false, createdAt: nil
        )
        #expect(weekly.currentPeriodStart(at: pacific(2026, 11, 8, 10), calendar: sundayFirst) == pacific(2026, 11, 8))

        let registration = PushRegistration(token: "t", env: "sandbox", timezone: "America/Los_Angeles", calendar: sundayFirst)
        #expect(try body(registration)["p_first_weekday"] as? Int == 1)
        #expect(try body(registration)["p_token"] as? String == "t")
        let mondayFirst = PushRegistration(token: "t", env: "sandbox", timezone: "UTC", calendar: calendar(firstWeekday: 2))
        #expect(try body(mondayFirst)["p_first_weekday"] as? Int == 2)
    }
}

// MARK: - Council review 2026-11-06: registration, sign-out and the daily random pick

@MainActor
struct PushRegistrarTests {
    private let tokenA = String(repeating: "a1", count: 32)
    private let tokenB = String(repeating: "b2", count: 32)

    /// Every server call, by function and the token it named.
    @MainActor
    final class Server {
        var calls: [(function: String, token: String)] = []
        var failing: Set<String> = []
    }

    private func makeRegistrar(_ server: Server, user: @escaping @MainActor () -> UUID?) -> (PushRegistrar, UserDefaults) {
        let defaults = UserDefaults(suiteName: "push-tests-\(UUID().uuidString)")!
        let registrar = PushRegistrar(defaults: defaults)
        registrar.currentUser = user
        registrar.call = { function, params in
            let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(params)) as? [String: Any]
            server.calls.append((function, json?["p_token"] as? String ?? ""))
            if server.failing.contains(function) { throw URLError(.notConnectedToInternet) }
        }
        return (registrar, defaults)
    }

    private func names(_ server: Server) -> [String] { server.calls.map { "\($0.function) \($0.token.prefix(2))" } }

    @Test func registersOnEveryForegroundNotOncePerDay() async {
        let server = Server()
        let me = UUID()
        let (registrar, _) = makeRegistrar(server) { me }
        var rearmed = 0
        registrar.onRegistered = { rearmed += 1 }
        await registrar.register(token: tokenA)
        await registrar.register(token: tokenA)
        #expect(server.calls.filter { $0.function == "register_push_device" }.count == 2,
                "a device row the server dropped comes back at the next foreground")
        #expect(registrar.serverDelivers(for: me))
        #expect(rearmed == 1, "the local copies go once, when the server starts delivering")
    }

    @Test func theServerIsToldWhetherThisPhoneArmedItsOwn() async throws {
        var sent: [Bool?] = []
        let me = UUID()
        let defaults = UserDefaults(suiteName: "push-tests-\(UUID().uuidString)")!
        let registrar = PushRegistrar(defaults: defaults)
        registrar.currentUser = { me }
        registrar.call = { _, params in
            let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(params)) as? [String: Any]
            sent.append(json?["p_armed_locally"] as? Bool)
        }
        await registrar.register(token: tokenA)
        await registrar.register(token: tokenB)
        #expect(sent == [true, false], "a served phone with a new token armed nothing, and is owed what is due")
    }

    @Test func aFailedRegistrationIsNotSentAgainWithoutTheFlag() async {
        let server = Server()
        server.failing = ["register_push_device"]
        let me = UUID()
        let (registrar, _) = makeRegistrar(server) { me }
        await registrar.register(token: tokenA)
        #expect(server.calls.filter { $0.function == "register_push_device" }.count == 1,
                "without the flag the server would guess what this phone armed")
    }

    @Test func aFailedFirstRegistrationTakesTheTokenBack() async {
        let server = Server()
        server.failing = ["register_push_device"]
        let me = UUID()
        let (registrar, _) = makeRegistrar(server) { me }
        await registrar.register(token: tokenA)
        #expect(names(server).last == "unregister_push_device a1", "the server may have it though the answer was lost")
        #expect(!registrar.serverDelivers(for: me), "so the phone keeps arming everything itself")
    }

    @Test func aTokenThatCouldNotBeTakenBackIsSettledByTheNextRegistration() async {
        let server = Server()
        server.failing = ["register_push_device", "unregister_push_device"]
        let me = UUID()
        let (registrar, defaults) = makeRegistrar(server) { me }
        await registrar.register(token: tokenA)
        #expect(PushRegistrar.hasPendingRelease(defaults), "the server may be delivering to this phone as well")
        server.failing = []
        var rearmed = 0
        registrar.onRegistered = { rearmed += 1 }
        await registrar.register(token: tokenA)
        #expect(!PushRegistrar.hasPendingRelease(defaults))
        #expect(registrar.serverDelivers(for: me))
        #expect(rearmed == 1, "the local copies go now that the server delivers")
    }

    @Test func aFailedRepeatRegistrationKeepsServing() async {
        let server = Server()
        let me = UUID()
        let (registrar, _) = makeRegistrar(server) { me }
        await registrar.register(token: tokenA)
        server.failing = ["register_push_device"]
        await registrar.register(token: tokenA)
        #expect(!server.calls.contains { $0.function == "unregister_push_device" })
        #expect(registrar.serverDelivers(for: me))
    }

    @Test func anOfflineSignOutLeavesTheTokenToTheNextAccount() async {
        let server = Server()
        var user = UUID()
        let old = user
        let (registrar, defaults) = makeRegistrar(server) { user }
        await registrar.register(token: tokenA)

        server.failing = ["unregister_push_device"]
        await registrar.unregister()
        #expect(PushRegistrar.hasPendingRelease(defaults), "the old account still holds it on the server")
        #expect(!registrar.serverDelivers(for: old), "and the phone arms locally meanwhile")

        server.failing = []
        user = UUID()
        await registrar.register(token: tokenA)
        #expect(!PushRegistrar.hasPendingRelease(defaults), "registering moved it to the new account")
        #expect(registrar.serverDelivers(for: user))
    }

    @Test func aTokenTheNewAccountDidNotRegisterIsStillReleased() async {
        let server = Server()
        var user = UUID()
        let (registrar, defaults) = makeRegistrar(server) { user }
        await registrar.register(token: tokenA)
        server.failing = ["unregister_push_device"]
        await registrar.unregister()

        server.failing = []
        user = UUID()
        server.calls = []
        await registrar.register(token: tokenB)
        #expect(names(server) == [
            "register_push_device b2", "register_push_device a1", "unregister_push_device a1"
        ])
        #expect(!PushRegistrar.hasPendingRelease(defaults))
    }

    @Test func deletingTheAccountLeavesNothingPending() async {
        let server = Server()
        let (registrar, defaults) = makeRegistrar(server) { UUID() }
        await registrar.register(token: tokenA)
        registrar.forget()
        #expect(!PushRegistrar.hasPendingRelease(defaults))
    }
}

struct DailyRandomAgreementTests {
    private let id = UUID(uuidString: "E7000000-0000-0000-0000-000000000001")!

    private var pacific: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return cal
    }

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        pacific.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func reminder(createdAt: Date) -> ReminderDTO {
        ReminderDTO(
            id: id, coupleId: UUID(), authorId: UUID(), targetId: UUID(),
            title: "Surprise", body: nil, loveLanguage: .words, triggerType: "random_window",
            fireAt: nil, rrule: "FREQ=DAILY", geofence: nil,
            windowStart: at(2030, 1, 1, 18), windowEnd: at(2030, 1, 1, 21), status: "scheduled",
            surpriseHiddenFromPartner: false, createdAt: createdAt
        )
    }

    /// supabase/tests/reliable_delivery_test.sql asserts the same instants on the server.
    @Test func thePhonePicksWhatTheServerPicks() {
        let day = pacific.startOfDay(for: at(2030, 5, 6, 12))
        let pick = NotificationScheduler.stablePick(in: at(2030, 5, 6, 18)...at(2030, 5, 6, 21), reminderId: id, day: day)
        let server = ISO8601DateFormatter().date(from: "2030-05-07T03:35:33Z")!.addingTimeInterval(0.5544)
        #expect(abs(pick.timeIntervalSince(server)) < 0.001, "\(pick)")
    }

    @Test func madeInsideTodaysWindowAfterTodaysMomentItComesAtTheServersMoment() throws {
        let made = at(2030, 5, 6, 20, 40)
        let plan = NotificationScheduler.plan(for: reminder(createdAt: made), now: made, calendar: pacific)
        let today = try #require(plan.first { $0.identifier == "\(id.uuidString).today" })
        let interval = try #require((today.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval)
        let server = ISO8601DateFormatter().date(from: "2030-05-07T03:57:25Z")!.addingTimeInterval(0.20852)
        #expect(abs(made.addingTimeInterval(interval).timeIntervalSince(server)) < 0.001)
    }
}
