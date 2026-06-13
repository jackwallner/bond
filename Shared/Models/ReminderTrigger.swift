import Foundation

public enum ReminderTrigger: Codable, Sendable, Hashable {
    case oneTime(fireAt: Date)
    case recurring(rrule: String, nextFire: Date)
    case location(geofence: Geofence, onEntry: Bool)
    case randomWindow(start: Date, end: Date)
    /// Fires once per day at a random moment inside a time-of-day window
    /// (e.g. "every day between 6pm and 9pm"). `start`/`end` carry the
    /// window's time of day; their calendar date is just the anchor day.
    case randomRecurring(start: Date, end: Date)

    public var kindRaw: String {
        switch self {
        case .oneTime:         "one_time"
        case .recurring:       "recurring"
        case .location:        "location"
        case .randomWindow:    "random_window"
        case .randomRecurring: "random_window"
        }
    }

    public var nextFireDate: Date? {
        switch self {
        case .oneTime(let d):           d
        case .recurring(_, let d):      d
        case .randomWindow(_, let e):   e
        case .randomRecurring(_, let e): e
        case .location:                 nil
        }
    }

    /// Future-aware next fire. For recurring triggers, walks the RRULE forward
    /// from the stored anchor until it lands after `reference`. The bare
    /// `nextFireDate` returns the stored anchor, which goes stale for
    /// recurring reminders once the anchor is in the past.
    public func upcomingFireDate(after reference: Date = .now) -> Date? {
        switch self {
        case .oneTime(let d):
            return d
        case .recurring(let rrule, let anchor):
            guard let preset = RecurrencePreset(rrule: rrule) else { return anchor }
            var next = anchor
            for _ in 0..<10_000 {
                if next > reference { return next }
                next = preset.nextOccurrence(after: next)
            }
            return next
        case .randomWindow(_, let end):
            return end
        case .randomRecurring:
            return nextWindow(after: reference)?.end
        case .location:
            return nil
        }
    }

    /// For `.randomRecurring`: the next daily window whose end is still ahead
    /// of `reference` - today's window if it hasn't closed yet, else
    /// tomorrow's. Returns nil for other trigger kinds.
    public func nextWindow(
        after reference: Date = .now, calendar: Calendar = .current
    ) -> (start: Date, end: Date)? {
        guard case .randomRecurring(let start, let end) = self else { return nil }
        let startComps = calendar.dateComponents([.hour, .minute], from: start)
        let endComps = calendar.dateComponents([.hour, .minute], from: end)
        var day = calendar.startOfDay(for: reference)
        for _ in 0..<2 {
            guard
                let windowStart = calendar.date(
                    bySettingHour: startComps.hour ?? 0,
                    minute: startComps.minute ?? 0, second: 0, of: day),
                let windowEnd = calendar.date(
                    bySettingHour: endComps.hour ?? 0,
                    minute: endComps.minute ?? 0, second: 0, of: day)
            else { return nil }
            if windowEnd > reference { return (windowStart, windowEnd) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = next
        }
        return nil
    }
}

public struct Geofence: Codable, Sendable, Hashable {
    public let latitude: Double
    public let longitude: Double
    public let radiusMeters: Double
    public let label: String

    public init(latitude: Double, longitude: Double, radiusMeters: Double, label: String) {
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.label = label
    }
}
