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
        case .daily:   "Every day"
        case .weekly:  "Every week"
        case .monthly: "Every month"
        case .yearly:  "Every year"
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
        let component: Calendar.Component = switch self {
        case .daily:   .day
        case .weekly:  .weekOfYear
        case .monthly: .month
        case .yearly:  .year
        }
        return calendar.date(byAdding: component, value: 1, to: date) ?? date
    }
}
