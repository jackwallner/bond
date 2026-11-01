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
        case .words: "Words of Affirmation"
        case .acts:  "Acts of Service"
        case .gifts: "Receiving Gifts"
        case .time:  "Quality Time"
        case .touch: "Physical Touch"
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
