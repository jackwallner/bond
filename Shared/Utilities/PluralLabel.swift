import Foundation

/// Count labels shown beside a number that is drawn separately ("12" over
/// "days to go"). A catalog plural variant has to contain its number, so these
/// labels cannot be plural keys themselves. Instead the catalog's
/// `"%lld plural category"` key returns the CLDR category for the user's
/// language ("few 3"), and each label has one whole key per category.
enum PluralLabel {
    enum Category: String {
        case one, few, many, other
    }

    static func category(_ count: Int) -> Category {
        let token = String(localized: "\(count) plural category")
        let word = token.split(separator: " ").first.map(String.init) ?? ""
        return Category(rawValue: word) ?? (count == 1 ? .one : .other)
    }

    /// "day streak", under the current streak count.
    static func dayStreak(_ count: Int) -> String {
        switch category(count) {
        case .one: String(localized: "day streak")
        case .few: String(localized: "day streak (few)")
        case .many: String(localized: "day streak (many)")
        case .other: String(localized: "day streak")
        }
    }

    /// "best streak", under the longest streak count.
    static func bestStreak(_ count: Int) -> String {
        switch category(count) {
        case .one: String(localized: "best streak")
        case .few: String(localized: "best streak (few)")
        case .many: String(localized: "best streak (many)")
        case .other: String(localized: "best streak")
        }
    }

    /// "day to go" / "days to go", beside the milestone countdown widget.
    static func daysToGo(_ count: Int) -> String {
        switch category(count) {
        case .one: String(localized: "day to go")
        case .few: String(localized: "days to go (few)")
        case .many: String(localized: "days to go (many)")
        case .other: String(localized: "days to go")
        }
    }
}
