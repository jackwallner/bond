import SwiftUI

public enum LoveLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case words
    case acts
    case gifts
    case time
    case touch

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .words: String(localized: "Words of Affirmation")
        case .acts:  String(localized: "Acts of Service")
        case .gifts: String(localized: "Receiving Gifts")
        case .time:  String(localized: "Quality Time")
        case .touch: String(localized: "Physical Touch")
        }
    }

    /// Whole-sentence insight for the least expressed language. One key per
    /// language so no translated title is lowercased or spliced into a sentence.
    public var leastExpressedInsight: String {
        switch self {
        case .words: String(localized: "Words of Affirmation is your least expressed love language. Consider adding more words of affirmation reminders.")
        case .acts:  String(localized: "Acts of Service is your least expressed love language. Consider adding more acts of service reminders.")
        case .gifts: String(localized: "Receiving Gifts is your least expressed love language. Consider adding more receiving gifts reminders.")
        case .time:  String(localized: "Quality Time is your least expressed love language. Consider adding more quality time reminders.")
        case .touch: String(localized: "Physical Touch is your least expressed love language. Consider adding more physical touch reminders.")
        }
    }

    /// Editor preview note when no other reminder uses this language. One whole
    /// sentence per language so the translated title can be inflected.
    public var firstReminderNote: String {
        switch self {
        case .words: String(localized: "Your first Words of Affirmation reminder.")
        case .acts:  String(localized: "Your first Acts of Service reminder.")
        case .gifts: String(localized: "Your first Receiving Gifts reminder.")
        case .time:  String(localized: "Your first Quality Time reminder.")
        case .touch: String(localized: "Your first Physical Touch reminder.")
        }
    }

    /// Editor preview note for `count` other reminders in this language (at
    /// least one). Each key is a plural on the count and a whole sentence.
    public func otherRemindersNote(_ count: Int) -> String {
        switch self {
        case .words: String(localized: "\(count) other reminders speak Words of Affirmation.")
        case .acts:  String(localized: "\(count) other reminders speak Acts of Service.")
        case .gifts: String(localized: "\(count) other reminders speak Receiving Gifts.")
        case .time:  String(localized: "\(count) other reminders speak Quality Time.")
        case .touch: String(localized: "\(count) other reminders speak Physical Touch.")
        }
    }

    public var symbolName: String {
        switch self {
        case .words: "quote.bubble.fill"
        case .acts:  "hands.sparkles.fill"
        case .gifts: "gift.fill"
        case .time:  "clock.fill"
        case .touch: "hand.raised.fingers.spread.fill"
        }
    }

    public var tint: Color {
        switch self {
        case .words: .pink
        case .acts:  .orange
        case .gifts: .purple
        case .time:  .blue
        // Touch was system red - indistinguishable from Words (.pink) in low
        // light. Deep terracotta keeps the warmth while reading distinct.
        case .touch: .bondTouchTerracotta
        }
    }

    /// `tint` for small text on the cream surface: system hues measure 2 to 3:1
    /// there. Light uses darkened hues that hold 4.5:1; dark keeps `tint`.
    public var textTint: Color {
        switch self {
        case .words: Color(light: Color(red: 0.761, green: 0.094, blue: 0.357), dark: tint)
        case .acts:  Color(light: Color(red: 0.600, green: 0.255, blue: 0.020), dark: tint)
        case .gifts: Color(light: Color(red: 0.482, green: 0.247, blue: 0.710), dark: tint)
        case .time:  Color(light: Color(red: 0.122, green: 0.373, blue: 0.800), dark: tint)
        case .touch: Color(light: Color(red: 0.600, green: 0.250, blue: 0.145), dark: tint)
        }
    }

    /// Solid fill behind white text (a selected chip). `tint` is lightened in
    /// dark mode for text on a dark card, which white cannot read on; these
    /// hold 4.5:1 against white in both appearances.
    public var chipFill: Color {
        switch self {
        case .words: Color(red: 0.761, green: 0.094, blue: 0.357)
        case .acts:  Color(red: 0.690, green: 0.314, blue: 0.039)
        case .gifts: Color(red: 0.482, green: 0.247, blue: 0.710)
        case .time:  Color(red: 0.122, green: 0.373, blue: 0.800)
        case .touch: Color(red: 0.659, green: 0.278, blue: 0.165)
        }
    }
}
