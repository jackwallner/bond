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

    // MARK: - Year boundary

    @Test func yearBoundary_dec31_advancesCorrectly() {
        let date = DateComponents(calendar: .current, year: 2000, month: 12, day: 31).date!
        let ref = DateComponents(calendar: .current, year: 2026, month: 12, day: 31).date!
        let m = MilestoneDTO(id: UUID(), coupleId: coupleId, kind: "custom", label: nil, date: date, recur: true)
        let next = m.nextOccurrence(reference: ref)
        #expect(next == ref)
    }
}
