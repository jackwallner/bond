import Foundation
import Testing

@testable import Bond

struct RecurrencePresetTests {
    // MARK: — RRULE strings

    @Test func daily_rrule() {
        #expect(RecurrencePreset.daily.rrule == "FREQ=DAILY")
    }

    @Test func weekly_rrule() {
        #expect(RecurrencePreset.weekly.rrule == "FREQ=WEEKLY")
    }

    @Test func monthly_rrule() {
        #expect(RecurrencePreset.monthly.rrule == "FREQ=MONTHLY")
    }

    @Test func yearly_rrule() {
        #expect(RecurrencePreset.yearly.rrule == "FREQ=YEARLY")
    }

    // MARK: — Init from RRULE string (round-trip)

    @Test func initFromExactMatch() {
        #expect(RecurrencePreset(rrule: "FREQ=DAILY") == .daily)
        #expect(RecurrencePreset(rrule: "FREQ=WEEKLY") == .weekly)
        #expect(RecurrencePreset(rrule: "FREQ=MONTHLY") == .monthly)
        #expect(RecurrencePreset(rrule: "FREQ=YEARLY") == .yearly)
    }

    @Test func initFromCaseInsensitive() {
        #expect(RecurrencePreset(rrule: "freq=daily") == .daily)
        #expect(RecurrencePreset(rrule: "Freq=Weekly") == .weekly)
    }

    @Test func initFromExtendedRRULE() {
        // Should still match by containing the preset string
        #expect(RecurrencePreset(rrule: "FREQ=WEEKLY;BYDAY=MO,WE,FR") == .weekly)
        #expect(RecurrencePreset(rrule: "FREQ=MONTHLY;BYMONTHDAY=15") == .monthly)
    }

    @Test func initFromUnrecognized_returnsNil() {
        #expect(RecurrencePreset(rrule: "FREQ=HOURLY") == nil)
        #expect(RecurrencePreset(rrule: "BOGUS") == nil)
        #expect(RecurrencePreset(rrule: "") == nil)
    }

    // MARK: — nextOccurrence date math

    @Test func daily_nextOccurrence() {
        let date = DateComponents(calendar: .current, year: 2026, month: 1, day: 1).date!
        let next = RecurrencePreset.daily.nextOccurrence(after: date)
        let expected = DateComponents(calendar: .current, year: 2026, month: 1, day: 2).date!
        #expect(next == expected)
    }

    @Test func weekly_nextOccurrence() {
        let date = DateComponents(calendar: .current, year: 2026, month: 1, day: 1).date!
        let next = RecurrencePreset.weekly.nextOccurrence(after: date)
        #expect(next > date)
    }

    @Test func monthly_nextOccurrence() {
        let date = DateComponents(calendar: .current, year: 2026, month: 1, day: 15).date!
        let next = RecurrencePreset.monthly.nextOccurrence(after: date)
        let expected = DateComponents(calendar: .current, year: 2026, month: 2, day: 15).date!
        #expect(next == expected)
    }

    @Test func yearly_nextOccurrence_leapYear() {
        let date = DateComponents(calendar: .current, year: 2024, month: 2, day: 29).date!
        let next = RecurrencePreset.yearly.nextOccurrence(after: date)
        // 2025 isn't a leap year, so Feb 29 -> Feb 28
        let expected = DateComponents(calendar: .current, year: 2025, month: 2, day: 28).date!
        #expect(next == expected)
    }
}
