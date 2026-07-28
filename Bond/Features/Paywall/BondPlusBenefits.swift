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
                    title: "Ideas matched to your partner",
                    detail: "Start with prompts based on what matters to them."
                ),
                BondPlusBenefit(
                    icon: "bell.badge.fill",
                    title: "Remember at the right moment",
                    detail: "Schedule thoughtful nudges before the moment passes."
                ),
                BondPlusBenefit(
                    icon: "sparkles",
                    title: "Learn what lands",
                    detail: "See which love languages you act on over time."
                )
            ]
        }
        return [
            BondPlusBenefit(
                icon: "questionmark.bubble.fill",
                title: "Daily Check-In",
                detail: "One question, together, every day."
            ),
            BondPlusBenefit(
                icon: "sparkles",
                title: "Love-language insights",
                detail: "Trends from what you both share."
            ),
            BondPlusBenefit(
                icon: "bell.badge.fill",
                title: "Surprise reminders",
                detail: "Nudge when you're near their spot."
            )
        ]
    }

    static func paywallSubheadline(isSolo: Bool) -> String {
        if isSolo {
            return "Turn what matters to your partner into actions you remember."
        }
        return "Stay close on purpose with the full Bond experience."
    }

    static func trialSubheadline(isSolo: Bool) -> String {
        if isSolo {
            return "Your personalized plan is ready. No payment today, cancel anytime."
        }
        return "Daily Check-In, insights, and thoughtful reminders. No payment today."
    }
}
