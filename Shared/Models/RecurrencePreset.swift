import Foundation

/// Minimal recurrence presets covering the v1 product needs.
/// Serialized to an iCalendar RRULE string (RFC 5545).
public enum RecurrencePreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case daily
    case weekly
    case monthly
    case yearly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .daily:   String(localized: "Every day")
        case .weekly:  String(localized: "Every week")
        case .monthly: String(localized: "Every month")
        case .yearly:  String(localized: "Every year")
        }
    }

    public var rrule: String {
        switch self {
        case .daily:   "FREQ=DAILY"
        case .weekly:  "FREQ=WEEKLY"
        case .monthly: "FREQ=MONTHLY"
        case .yearly:  "FREQ=YEARLY"
        }
    }

    public init?(rrule: String) {
        let normalized = rrule.uppercased()
        for preset in RecurrencePreset.allCases where normalized.contains(preset.rrule) {
            self = preset
            return
        }
        return nil
    }

    public func nextOccurrence(after date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: step, value: 1, to: date) ?? date
    }

    private var step: Calendar.Component {
        switch self {
        case .daily:   .day
        case .weekly:  .weekOfYear
        case .monthly: .month
        case .yearly:  .year
        }
    }

    /// The `n`-th occurrence counted from the anchor in whole steps, so a
    /// monthly reminder on the 31st lands on the last day of a short month and
    /// is back on the 31st after it, as the server counts it
    /// (`reminder_next_push_at`). Stepping from the previous occurrence drifted
    /// to the 28th for good.
    public func occurrence(_ n: Int, from anchor: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: step, value: n, to: anchor) ?? anchor
    }

    /// Index of the first occurrence strictly after `reference`.
    public func firstIndex(after reference: Date, anchor: Date, calendar: Calendar = .current) -> Int {
        guard anchor <= reference else { return 0 }
        let elapsed = calendar.dateComponents([step], from: anchor, to: reference).value(for: step) ?? 0
        var n = max(0, elapsed - 1)
        while occurrence(n, from: anchor, calendar: calendar) <= reference { n += 1 }
        return n
    }

    /// The first occurrence strictly after `reference`.
    public func firstOccurrence(after reference: Date, anchor: Date, calendar: Calendar = .current) -> Date {
        occurrence(firstIndex(after: reference, anchor: anchor, calendar: calendar), from: anchor, calendar: calendar)
    }
}
