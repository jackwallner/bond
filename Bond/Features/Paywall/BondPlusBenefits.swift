import Foundation

struct BondPlusBenefit: Identifiable, Hashable {
    let icon: String
    let title: String
    let detail: String

    var id: String { title }
}

enum BondPlusBenefits {
    static func benefits(isSolo: Bool) -> [BondPlusBenefit] {
        if isSolo {
            return [
                BondPlusBenefit(
                    icon: "square.stack.fill",
                    title: String(localized: "Ideas matched to your partner"),
                    detail: String(localized: "Start with prompts based on what matters to them.")
                ),
                BondPlusBenefit(
                    icon: "bell.badge.fill",
                    title: String(localized: "Remember at the right moment"),
                    detail: String(localized: "Schedule thoughtful nudges before the moment passes.")
                ),
                BondPlusBenefit(
                    icon: "sparkles",
                    title: String(localized: "Learn what lands"),
                    detail: String(localized: "See which love languages you act on over time.")
                )
            ]
        }
        return [
            BondPlusBenefit(
                icon: "questionmark.bubble.fill",
                title: String(localized: "Daily Check-In"),
                detail: String(localized: "One question, together, every day.")
            ),
            BondPlusBenefit(
                icon: "sparkles",
                title: String(localized: "Love-language insights"),
                detail: String(localized: "Trends from what you both share.")
            ),
            BondPlusBenefit(
                icon: "bell.badge.fill",
                title: String(localized: "Surprise reminders"),
                detail: String(localized: "Nudge when you're near their spot.")
            )
        ]
    }

    static func paywallSubheadline(isSolo: Bool) -> String {
        if isSolo {
            return String(localized: "Turn what matters to your partner into actions you remember.")
        }
        return String(localized: "Stay close on purpose with the full Little Gestures experience.")
    }

    static func trialSubheadline(isSolo: Bool) -> String {
        if isSolo {
            return String(localized: "Your personalized plan is ready. No payment today, cancel anytime.")
        }
        return String(localized: "Daily Check-In, insights, and thoughtful reminders. No payment today.")
    }
}
