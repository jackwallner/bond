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

    // MARK: - Completion Rate

    /// Overall completion rate (acted / total events) as percentage
    public func completionRate() -> Double {
        let total = events.count
        guard total > 0 else { return 0 }
        let acted = events.filter { $0.actedAt != nil }.count
        return (Double(acted) / Double(total)) * 100
    }

    /// Completion rate per love language
    public func completionRates() -> [(LoveLanguage, rate: Double)] {
        let reminderMap = Dictionary(uniqueKeysWithValues: reminders.map { ($0.id, $0) })
        var langEvents: [LoveLanguage: (total: Int, acted: Int)] = [:]

        for e in events {
            guard let reminder = reminderMap[e.reminderId] else { continue }
            let acted = e.actedAt != nil ? 1 : 0
            let current = langEvents[reminder.loveLanguage] ?? (0, 0)
            langEvents[reminder.loveLanguage] = (current.total + 1, current.acted + acted)
        }

        return LoveLanguage.allCases.map { lang in
            let stats = langEvents[lang] ?? (0, 0)
            let rate = stats.total > 0 ? (Double(stats.acted) / Double(stats.total)) * 100 : 0
            return (lang, rate)
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
            result.append("\(neglected.0.title) is your least expressed love language — consider adding more \(neglected.0.title.lowercased()) reminders.")
        }

        let rate = completionRate()
        if rate > 75 {
            result.append("Excellent follow-through! You're acting on \(Int(rate))% of your reminders.")
        } else if rate > 50 {
            result.append("Good progress — you're completing \(Int(rate))% of reminders. Try to act on more when they fire.")
        } else if rate > 0 {
            result.append("You've completed \(Int(rate))% of reminders. Small consistent actions build strong habits.")
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
