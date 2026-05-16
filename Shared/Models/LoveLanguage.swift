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
        // Touch was system red — indistinguishable from Words (.pink) in low
        // light. Deep terracotta keeps the warmth while reading distinct.
        case .touch: .bondTouchTerracotta
        }
    }
}
