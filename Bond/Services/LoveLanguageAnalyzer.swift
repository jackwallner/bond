import Foundation

/// Non-AI love language analyzer using pure statistics on reminder and event data.
/// Computes balance scores, trends, and actionable insights programmatically.
public struct LoveLanguageAnalyzer: Sendable {
    private let reminders: [ReminderDTO]
    private let events: [ReminderEventDTO]

    public init(reminders: [ReminderDTO], events: [ReminderEventDTO]) {
        self.reminders = reminders
        self.events = events
    }

    // MARK: - Core Analysis

    /// Count of reminders per love language
    public func reminderCounts() -> [(LoveLanguage, Int)] {
        var dict: [LoveLanguage: Int] = [:]
        for r in reminders { dict[r.loveLanguage, default: 0] += 1 }
        return LoveLanguage.allCases.map { ($0, dict[$0] ?? 0) }
    }

    /// Count of completed (acted) events per love language
    public func completionCounts() -> [(LoveLanguage, Int)] {
        let reminderMap = Dictionary(uniqueKeysWithValues: reminders.map { ($0.id, $0) })
        var dict: [LoveLanguage: Int] = [:]
        for e in events where e.actedAt != nil {
            if let reminder = reminderMap[e.reminderId] {
                dict[reminder.loveLanguage, default: 0] += 1
            }
        }
        return LoveLanguage.allCases.map { ($0, dict[$0] ?? 0) }
    }

    /// Total events per love language (fired, whether acted or not)
    public func eventCounts() -> [(LoveLanguage, Int)] {
        let reminderMap = Dictionary(uniqueKeysWithValues: reminders.map { ($0.id, $0) })
        var dict: [LoveLanguage: Int] = [:]
        for e in events {
            if let reminder = reminderMap[e.reminderId] {
                dict[reminder.loveLanguage, default: 0] += 1
            }
        }
        return LoveLanguage.allCases.map { ($0, dict[$0] ?? 0) }
    }

    // MARK: - Balance Analysis

    /// Balance score from 0 to 100. 100 = perfectly even across all 5 languages.
    /// Uses inverse variance from ideal 20% distribution.
    public func balanceScore() -> Double {
        let counts = reminderCounts()
        let total = counts.map(\.1).reduce(0, +)
        guard total > 0 else { return 0 }

        let ideal = Double(total) / 5.0
        let variance = counts.map { pow(Double($0.1) - ideal, 2) }.reduce(0, +) / 5.0
        let maxVariance = pow(Double(total), 2) / 5.0
        let normalized = maxVariance > 0 ? 1.0 - (variance / maxVariance) : 1.0
        return max(0, normalized * 100)
    }

    /// Which love language is most neglected (lowest count), and by how much
    public func mostNeglected() -> (LoveLanguage, gap: Double)? {
        let counts = reminderCounts()
        let total = counts.map(\.1).reduce(0, +)
        guard total > 0 else { return nil }
        let ideal = Double(total) / 5.0
        return counts.min { $0.1 < $1.1 }.map { lang, count in
            (lang, gap: ideal - Double(count))
        }
    }

    /// Which love language is most used (highest count)
    public func mostUsed() -> (LoveLanguage, count: Int)? {
        reminderCounts().max { $0.1 < $1.1 }
    }

    // MARK: - Follow-through (completion vs. expected occurrences)

    // Events are only written when someone marks a reminder done, so
    // "acted / total events" was always 100% (or 0% before the acted_at fix).
    // Real follow-through compares completions against how many occurrences
    // the schedule *expected* in the window: a daily reminder expects 7 in a
    // week; a one-time reminder that came due expects 1.

    public struct FollowThrough: Identifiable, Sendable {
        public let reminder: ReminderDTO
        public let expected: Int
        public let completed: Int
        public var id: UUID { reminder.id }
    }

    /// Per-reminder follow-through for repeating reminders over the trailing
    /// `days` days. One row per repeating reminder that expected at least one
    /// occurrence in the window.
    public func followThrough(days: Int = 7, now: Date = .now) -> [FollowThrough] {
        let calendar = Calendar.current
        guard let windowStart = calendar.date(
            byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)
        ) else { return [] }

        return reminders.compactMap { reminder in
            let starts = periodStarts(for: reminder, since: windowStart, now: now, calendar: calendar)
            guard !starts.isEmpty, let preset = recurrencePreset(for: reminder) else { return nil }
            let actedDates = events
                .filter { $0.reminderId == reminder.id }
                .compactMap(\.actedAt)
            let completed = starts.filter { start in
                let end = preset.nextOccurrence(after: start, calendar: calendar)
                return actedDates.contains { $0 >= start && $0 < end }
            }.count
            return FollowThrough(reminder: reminder, expected: starts.count, completed: completed)
        }
        .sorted { $0.expected > $1.expected }
    }

    /// Expected vs. completed per love language over the trailing `days`
    /// days. Repeating reminders contribute one expectation per period;
    /// one-shot reminders that came due in the window contribute one.
    public func completionByLanguage(days: Int = 7, now: Date = .now)
        -> [(LoveLanguage, expected: Int, completed: Int)]
    {
        let calendar = Calendar.current
        let windowStart = calendar.date(
            byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)
        ) ?? now

        var tally: [LoveLanguage: (expected: Int, completed: Int)] = [:]
        let repeating = followThrough(days: days, now: now)
        for item in repeating {
            let current = tally[item.reminder.loveLanguage] ?? (0, 0)
            tally[item.reminder.loveLanguage] = (
                current.expected + item.expected, current.completed + item.completed
            )
        }
        for reminder in reminders where recurrencePreset(for: reminder) == nil {
            guard let due = reminder.fireAt, due >= windowStart, due <= now else { continue }
            let done = events.contains { $0.reminderId == reminder.id && $0.actedAt != nil }
            let current = tally[reminder.loveLanguage] ?? (0, 0)
            tally[reminder.loveLanguage] = (current.expected + 1, current.completed + (done ? 1 : 0))
        }

        return LoveLanguage.allCases.map { lang in
            let stats = tally[lang] ?? (0, 0)
            return (lang, stats.expected, stats.completed)
        }
    }

    /// Overall follow-through (0–100) over the trailing `days` days, or nil
    /// when nothing was expected yet.
    public func completionRate(days: Int = 7, now: Date = .now) -> Double? {
        let perLanguage = completionByLanguage(days: days, now: now)
        let expected = perLanguage.map(\.expected).reduce(0, +)
        guard expected > 0 else { return nil }
        let completed = perLanguage.map(\.completed).reduce(0, +)
        return Double(completed) / Double(expected) * 100
    }

    private func recurrencePreset(for reminder: ReminderDTO) -> RecurrencePreset? {
        switch reminder.trigger {
        case .recurring(let rrule, _): return RecurrencePreset(rrule: rrule) ?? .daily
        case .randomRecurring:         return .daily
        default:                       return nil
        }
    }

    /// Period start dates for a repeating reminder that overlap the window
    /// and the reminder's lifetime, oldest first.
    private func periodStarts(
        for reminder: ReminderDTO, since windowStart: Date, now: Date, calendar: Calendar
    ) -> [Date] {
        guard let preset = recurrencePreset(for: reminder),
              var start = reminder.currentPeriodStart(at: now, calendar: calendar)
        else { return [] }

        let born = reminder.createdAt ?? .distantPast
        var starts: [Date] = []
        for _ in 0..<60 {
            let end = preset.nextOccurrence(after: start, calendar: calendar)
            // A period counts if it overlaps both the window and the time the
            // reminder has existed (keyed on the period's end so a weekly or
            // monthly period that closes inside the window still counts).
            if end <= windowStart || end <= born { break }
            starts.append(start)
            guard let previous = calendar.date(
                byAdding: periodComponent(for: preset), value: -1, to: start
            ) else { break }
            start = previous
        }
        return starts.reversed()
    }

    private func periodComponent(for preset: RecurrencePreset) -> Calendar.Component {
        switch preset {
        case .daily:   .day
        case .weekly:  .weekOfYear
        case .monthly: .month
        case .yearly:  .year
        }
    }

    // MARK: - Trends

    /// Weekly trend data for the chart
    public struct WeeklyTrend: Identifiable, Sendable {
        public let id: String
        public let weekStart: Date
        public let counts: [(LoveLanguage, Int)]

        public init(weekStart: Date, counts: [(LoveLanguage, Int)]) {
            self.id = ISO8601DateFormatter().string(from: weekStart)
            self.weekStart = weekStart
            self.counts = counts
        }
    }

    /// Compute weekly trends from events
    public func weeklyTrends() -> [WeeklyTrend] {
        let reminderMap = Dictionary(uniqueKeysWithValues: reminders.map { ($0.id, $0) })
        var weeks: [Date: [LoveLanguage: Int]] = [:]
        let calendar = Calendar.current

        for e in events {
            guard let reminder = reminderMap[e.reminderId] else { continue }
            guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: e.firedAt)) else { continue }
            weeks[weekStart, default: [:]][reminder.loveLanguage, default: 0] += 1
        }

        return weeks.sorted { $0.key < $1.key }.map { date, dict in
            let counts = LoveLanguage.allCases.map { ($0, dict[$0] ?? 0) }
            return WeeklyTrend(weekStart: date, counts: counts)
        }
    }

    // MARK: - Insights

    /// Generate human-readable insights from the data
    public func insights() -> [String] {
        var result: [String] = []

        let total = reminders.count
        guard total > 0 else { return [] }

        let balance = balanceScore()
        if balance < 30 {
            result.append("Your love language expression is heavily imbalanced. Try adding reminders in your neglected areas.")
        } else if balance < 60 {
            result.append("You have a moderate spread of love languages. A few more in your lowest area could bring balance.")
        } else {
            result.append("Great balance! You're expressing love across all five languages.")
        }

        if let neglected = mostNeglected() {
            result.append("\(neglected.0.title) is your least expressed love language. Consider adding more \(neglected.0.title.lowercased()) reminders.")
        }

        if let rate = completionRate() {
            if rate > 75 {
                result.append("Excellent follow-through! You completed \(Int(rate))% of what was due this week.")
            } else if rate > 50 {
                result.append("Good progress: \(Int(rate))% of this week's reminders done. Try to act on more when they fire.")
            } else {
                result.append("You completed \(Int(rate))% of this week's reminders. Small consistent actions build strong habits.")
            }
        }

        return result
    }

    // MARK: - Streak

    /// Current completion streak (consecutive days with at least one acted event)
    public func currentStreak() -> Int {
        let actedDates = Set(events.filter { $0.actedAt != nil }.map { 
            Calendar.current.startOfDay(for: $0.actedAt ?? $0.firedAt)
        })

        guard !actedDates.isEmpty else { return 0 }

        let calendar = Calendar.current
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())

        // No completion *yet* today shouldn't read as a broken streak - the
        // day isn't over. Anchor on yesterday and let today extend it.
        if !actedDates.contains(checkDate),
           let yesterday = calendar.date(byAdding: .day, value: -1, to: checkDate) {
            checkDate = yesterday
        }

        while actedDates.contains(checkDate) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prev
        }

        return streak
    }

    /// Longest streak
    public func longestStreak() -> Int {
        let actedDates = Set(events.filter { $0.actedAt != nil }.map { 
            Calendar.current.startOfDay(for: $0.actedAt ?? $0.firedAt)
        }).sorted()

        guard !actedDates.isEmpty else { return 0 }

        var longest = 1
        var current = 1
        let calendar = Calendar.current

        for i in 1..<actedDates.count {
            let diff = calendar.dateComponents([.day], from: actedDates[i-1], to: actedDates[i]).day ?? 0
            if diff == 1 {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }

        return longest
    }
}
