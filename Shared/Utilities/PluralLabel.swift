import Foundation

/// Count labels shown beside a number that is drawn separately ("12" over
/// "days to go"). A catalog plural variant has to contain its number, so these
/// labels cannot be plural keys themselves. Instead the catalog's
/// `"%lld plural category"` key returns the CLDR category for the user's
/// language ("few 3"), and each label has one whole key per category.
///
/// All six CLDR categories are reachable (Arabic uses every one). `one` and
/// `other` use the bare key; the rest use `(zero)`, `(two)`, `(few)` and
/// `(many)` keys, which carry an `en` value so English never shows the key.
enum PluralLabel {
    enum Category: String, CaseIterable {
        case zero, one, two, few, many, other
    }

    static func category(_ count: Int) -> Category {
        category(token: String(localized: "\(count) plural category"), count: count)
    }

    /// Reads the category word out of a `"%lld plural category"` result.
    static func category(token: String, count: Int) -> Category {
        let word = token.split(separator: " ").first.map(String.init) ?? ""
        return Category(rawValue: word) ?? (count == 1 ? .one : .other)
    }

    /// "day streak", under the current streak count.
    static func dayStreak(_ count: Int) -> String {
        dayStreak(for: category(count))
    }

    static func dayStreak(for category: Category) -> String {
        switch category {
        case .zero:  String(localized: "day streak (zero)")
        case .one:   String(localized: "day streak")
        case .two:   String(localized: "day streak (two)")
        case .few:   String(localized: "day streak (few)")
        case .many:  String(localized: "day streak (many)")
        case .other: String(localized: "day streak")
        }
    }

    /// "best streak", under the longest streak count.
    static func bestStreak(_ count: Int) -> String {
        bestStreak(for: category(count))
    }

    static func bestStreak(for category: Category) -> String {
        switch category {
        case .zero:  String(localized: "best streak (zero)")
        case .one:   String(localized: "best streak")
        case .two:   String(localized: "best streak (two)")
        case .few:   String(localized: "best streak (few)")
        case .many:  String(localized: "best streak (many)")
        case .other: String(localized: "best streak")
        }
    }

    /// "day to go" / "days to go", beside the milestone countdown widget.
    static func daysToGo(_ count: Int) -> String {
        daysToGo(for: category(count))
    }

    static func daysToGo(for category: Category) -> String {
        switch category {
        case .zero:  String(localized: "days to go (zero)")
        case .one:   String(localized: "day to go")
        case .two:   String(localized: "days to go (two)")
        case .few:   String(localized: "days to go (few)")
        case .many:  String(localized: "days to go (many)")
        case .other: String(localized: "days to go")
        }
    }
}
