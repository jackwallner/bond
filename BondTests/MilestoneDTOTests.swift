import Foundation
import Testing

@testable import Bond

struct MilestoneDTOTests {
    private let coupleId = UUID()

    // MARK: — nextOccurrence (non-recurring)

    @Test func nonRecurring_returnsDate() {
        let date = DateComponents(calendar: .current, year: 2030, month: 6, day: 15).date!
        let m = MilestoneDTO(id: UUID(), coupleId: coupleId, kind: "anniversary", label: nil, date: date, recur: false)
        #expect(m.nextOccurrence() == date)
    }

    // MARK: — nextOccurrence (recurring yearly)

    @Test func recurring_beforeReference_advancesYear() {
        let date = DateComponents(calendar: .current, year: 2000, month: 1, day: 1).date!
        let ref = DateComponents(calendar: .current, year: 2026, month: 6, day: 1).date!
        let m = MilestoneDTO(id: UUID(), coupleId: coupleId, kind: "anniversary", label: nil, date: date, recur: true)
        let next = m.nextOccurrence(reference: ref)
        // Should advance to 2027-01-01 since 2026-01-01 is already past
        let expected = DateComponents(calendar: .current, year: 2027, month: 1, day: 1).date!
        #expect(next == expected)
    }

    @Test func recurring_afterReference_staysSameYear() {
        let date = DateComponents(calendar: .current, year: 2000, month: 12, day: 25).date!
        let ref = DateComponents(calendar: .current, year: 2026, month: 6, day: 1).date!
        let m = MilestoneDTO(id: UUID(), coupleId: coupleId, kind: "anniversary", label: nil, date: date, recur: true)
        let next = m.nextOccurrence(reference: ref)
        // 2026-12-25 is after reference, so should stay in 2026
        let expected = DateComponents(calendar: .current, year: 2026, month: 12, day: 25).date!
        #expect(next == expected)
    }

    @Test func recurring_sameDay_referenceIsThatDay() {
        let date = DateComponents(calendar: .current, year: 2000, month: 7, day: 4).date!
        let ref = DateComponents(calendar: .current, year: 2026, month: 7, day: 4).date!
        let m = MilestoneDTO(id: UUID(), coupleId: coupleId, kind: "anniversary", label: nil, date: date, recur: true)
        let next = m.nextOccurrence(reference: ref)
        let expected = DateComponents(calendar: .current, year: 2026, month: 7, day: 4).date!
        #expect(next == expected)
    }

    // MARK: - Leap year edge cases

    @Test func leapYear_Feb29_inNonLeapYear_rollsToMarch1() {
        let date = DateComponents(calendar: .current, year: 2020, month: 2, day: 29).date!
        let ref = DateComponents(calendar: .current, year: 2023, month: 2, day: 1).date!
        let m = MilestoneDTO(id: UUID(), coupleId: coupleId, kind: "birthday", label: nil, date: date, recur: true)
        let next = m.nextOccurrence(reference: ref)
        let expected = DateComponents(calendar: .current, year: 2023, month: 3, day: 1).date!
        #expect(next == expected)
    }

    @Test func leapYear_Feb29_inLeapYear_staysFeb29() {
        let date = DateComponents(calendar: .current, year: 2020, month: 2, day: 29).date!
        let ref = DateComponents(calendar: .current, year: 2024, month: 1, day: 1).date!
        let m = MilestoneDTO(id: UUID(), coupleId: coupleId, kind: "birthday", label: nil, date: date, recur: true)
        let next = m.nextOccurrence(reference: ref)
        let expected = DateComponents(calendar: .current, year: 2024, month: 2, day: 29).date!
        #expect(next == expected)
    }

    @Test func leapYear_Feb29_onLeapYearDay_returnsSameDay() {
        let date = DateComponents(calendar: .current, year: 2020, month: 2, day: 29).date!
        let ref = DateComponents(calendar: .current, year: 2024, month: 2, day: 29).date!
        let m = MilestoneDTO(id: UUID(), coupleId: coupleId, kind: "birthday", label: nil, date: date, recur: true)
        let next = m.nextOccurrence(reference: ref)
        #expect(next == ref)
    }

    // MARK: - Codable (Postgres `date` column is a bare y-m-d string)

    @Test func decode_bareDateString_parsesToLocalMidnight() throws {
        let json = """
        {"id":"\(UUID().uuidString)","couple_id":"\(coupleId.uuidString)",
         "kind":"anniversary","label":"Us","date":"2026-03-05","recur":true,
         "created_at":null}
        """
        let m = try JSONDecoder().decode(MilestoneDTO.self, from: Data(json.utf8))
        let expected = DateComponents(calendar: .current, year: 2026, month: 3, day: 5).date!
        #expect(m.date == expected)
        #expect(m.label == "Us")
        #expect(m.recur)
    }

    @Test func encode_emitsBareDateString() throws {
        let date = DateComponents(calendar: .current, year: 2026, month: 3, day: 5).date!
        let m = MilestoneDTO(id: UUID(), coupleId: coupleId, kind: "anniversary", label: nil, date: date, recur: true)
        let data = try JSONEncoder().encode(m)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["date"] as? String == "2026-03-05")
    }

    @Test func codable_roundTrip_preservesCalendarDay() throws {
        let date = DateComponents(calendar: .current, year: 2024, month: 2, day: 29).date!
        let m = MilestoneDTO(id: UUID(), coupleId: coupleId, kind: "birthday", label: "Leap", date: date, recur: true)
        let decoded = try JSONDecoder().decode(MilestoneDTO.self, from: JSONEncoder().encode(m))
        #expect(decoded.date == m.date)
        #expect(decoded == m)
    }

    // MARK: - Year boundary

    @Test func yearBoundary_dec31_advancesCorrectly() {
        let date = DateComponents(calendar: .current, year: 2000, month: 12, day: 31).date!
        let ref = DateComponents(calendar: .current, year: 2026, month: 12, day: 31).date!
        let m = MilestoneDTO(id: UUID(), coupleId: coupleId, kind: "custom", label: nil, date: date, recur: true)
        let next = m.nextOccurrence(reference: ref)
        #expect(next == ref)
    }

    // MARK: - The day itself, with the clock past midnight
    //
    // Every case above hands in a midnight reference, which hides that the app
    // asks at 2 pm: the milestone day (local midnight) is already "before"
    // `.now`, so the next occurrence jumped a year ahead on the day itself.

    private var pacific: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private func pacificDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        pacific.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func yearlyMilestone(month: Int, day: Int) -> MilestoneDTO {
        MilestoneDTO(
            id: UUID(), coupleId: coupleId, kind: "anniversary", label: "Us",
            date: pacificDate(2020, month, day), recur: true
        )
    }

    @Test func recurring_onTheDay_atAfternoon_isToday() {
        let m = yearlyMilestone(month: 11, day: 5)
        let now = pacificDate(2026, 11, 5, hour: 14, minute: 30)
        #expect(m.nextOccurrence(reference: now, calendar: pacific) == pacificDate(2026, 11, 5))
    }

    @Test func recurring_onTheDay_justAfterMidnight_isToday() {
        let m = yearlyMilestone(month: 11, day: 5)
        let now = pacificDate(2026, 11, 5, hour: 0, minute: 1)
        #expect(m.nextOccurrence(reference: now, calendar: pacific) == pacificDate(2026, 11, 5))
    }

    @Test func recurring_theDayAfter_advancesToNextYear() {
        let m = yearlyMilestone(month: 11, day: 5)
        let now = pacificDate(2026, 11, 6, hour: 0, minute: 1)
        #expect(m.nextOccurrence(reference: now, calendar: pacific) == pacificDate(2027, 11, 5))
    }

    @Test func daysUntil_dayBefore_atAfternoon_isOne() {
        let m = yearlyMilestone(month: 11, day: 5)
        let now = pacificDate(2026, 11, 4, hour: 14)
        #expect(m.daysUntilNextOccurrence(reference: now, calendar: pacific) == 1)
    }

    @Test func daysUntil_onTheDay_isZero() {
        let m = yearlyMilestone(month: 11, day: 5)
        let now = pacificDate(2026, 11, 5, hour: 14)
        #expect(m.daysUntilNextOccurrence(reference: now, calendar: pacific) == 0)
    }

    @Test func daysUntil_countsCalendarDaysAcrossTheFallDSTChange() {
        // US clocks go back on 2026-11-01, so Oct 31 22:00 to Nov 2 00:00 is
        // 49 hours but two calendar days.
        let m = yearlyMilestone(month: 11, day: 2)
        let now = pacificDate(2026, 10, 31, hour: 22)
        #expect(m.daysUntilNextOccurrence(reference: now, calendar: pacific) == 2)
    }

    @Test func daysUntil_oneTimeMilestoneInThePast_isZero() {
        let m = MilestoneDTO(
            id: UUID(), coupleId: coupleId, kind: "custom", label: nil,
            date: pacificDate(2026, 1, 10), recur: false
        )
        let now = pacificDate(2026, 6, 1, hour: 9)
        #expect(m.daysUntilNextOccurrence(reference: now, calendar: pacific) == 0)
    }

    @Test func widgetCountdown_usesCalendarDays() {
        let next = WidgetSnapshot.NextMilestone(
            label: "Us", kind: "anniversary", occursOn: pacificDate(2026, 11, 5)
        )
        #expect(next.daysAway(from: pacificDate(2026, 11, 4, hour: 14), calendar: pacific) == 1)
        #expect(next.daysAway(from: pacificDate(2026, 11, 5, hour: 14), calendar: pacific) == 0)
        #expect(next.daysAway(from: pacificDate(2026, 11, 7, hour: 14), calendar: pacific) == 0)
    }
}


/// The milestone list reaches two places that the Milestones tab does not draw:
/// the widget snapshot and the local notifications. Both have to follow the list
/// from the first launch, not only after the tab has been opened.
@MainActor
@Suite(.serialized)
struct MilestonesServiceTests {
    private let coupleId = UUID()

    private func milestone(_ label: String) -> MilestoneDTO {
        MilestoneDTO(
            id: UUID(), coupleId: coupleId, kind: "anniversary", label: label,
            date: DateComponents(calendar: .current, year: 2020, month: 6, day: 1).date!, recur: true
        )
    }

    private func service() -> MilestonesService {
        let pairing = PairingService()
        pairing.coupleId = coupleId
        let service = MilestonesService(pairing: pairing)
        service.scheduleNotifications = { _, _ in }
        return service
    }

    @Test func refresh_publishesTheLoadedMilestones() async {
        let ours = milestone("Our anniversary")
        let service = service()
        service.loadRows = { _ in [ours] }
        var published: [MilestoneDTO]?
        service.onChange = { published = $0 }

        await service.refresh(requestAuthIfNeeded: false)

        #expect(service.milestones == [ours])
        #expect(published == [ours])
    }

    @Test func refresh_thatFails_publishesNothing() async {
        let service = service()
        service.loadRows = { _ in throw URLError(.notConnectedToInternet) }
        var published: [MilestoneDTO]?
        service.onChange = { published = $0 }

        await service.refresh(requestAuthIfNeeded: false)

        #expect(published == nil)
        #expect(service.lastError != nil)
    }

    @Test func delete_publishesTheRemainingMilestones() async throws {
        let keep = milestone("Keep")
        let drop = milestone("Drop")
        let service = service()
        service.loadRows = { _ in [keep, drop] }
        service.deleteRow = { _ in }
        await service.refresh(requestAuthIfNeeded: false)
        var published: [MilestoneDTO]?
        service.onChange = { published = $0 }

        try await service.delete(drop)

        #expect(published == [keep])
    }

    @Test func refresh_forwardsWhetherSchedulingMayAskForPermission() async {
        let service = service()
        service.loadRows = { _ in [] }
        var asked: [Bool] = []
        service.scheduleNotifications = { _, mayAsk in asked.append(mayAsk) }

        await service.refresh(requestAuthIfNeeded: false)
        await service.refresh()

        #expect(asked == [false, true])
    }
}
