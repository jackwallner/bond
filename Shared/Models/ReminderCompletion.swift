import Foundation

// Per-occurrence completion semantics. A one-shot reminder (one time, at a
// place, single random surprise) is completed forever by one acted event. A
// repeating reminder is completed only for its current period — done today,
// back tomorrow — which is what makes "mark it done" meaningful for a daily
// habit instead of a one-way trip to the Handled pile.
public extension ReminderDTO {
    /// True when this reminder comes back on a schedule (recurring rrule or
    /// daily random window), so completion applies per period.
    var repeatsOnSchedule: Bool {
        currentPeriodStart(at: .now) != nil
    }

    /// Start of the completion period containing `now`, or nil when
    /// completion is one-shot.
    func currentPeriodStart(at now: Date = .now, calendar: Calendar = .current) -> Date? {
        switch trigger {
        case .recurring(let rrule, _):
            let preset = RecurrencePreset(rrule: rrule) ?? .daily
            switch preset {
            case .daily:   return calendar.startOfDay(for: now)
            case .weekly:  return calendar.dateInterval(of: .weekOfYear, for: now)?.start
            case .monthly: return calendar.dateInterval(of: .month, for: now)?.start
            case .yearly:  return calendar.dateInterval(of: .year, for: now)?.start
            }
        case .randomRecurring:
            return calendar.startOfDay(for: now)
        default:
            return nil
        }
    }

    /// Whether the reminder counts as done right now, given the acted events.
    func isCompleted(in events: [ReminderEventDTO], at now: Date = .now) -> Bool {
        let acted = events.filter { $0.reminderId == id && $0.actedAt != nil }
        guard let periodStart = currentPeriodStart(at: now) else {
            return !acted.isEmpty
        }
        return acted.contains { ($0.actedAt ?? $0.firedAt) >= periodStart }
    }

    /// The acted event covering the current period (used to undo a
    /// completion). For one-shot reminders, any acted event.
    func currentCompletionEvent(in events: [ReminderEventDTO], at now: Date = .now) -> ReminderEventDTO? {
        let acted = events.filter { $0.reminderId == id && $0.actedAt != nil }
        guard let periodStart = currentPeriodStart(at: now) else { return acted.first }
        return acted.first { ($0.actedAt ?? $0.firedAt) >= periodStart }
    }
}
