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
                    icon: "bell.badge.fill",
                    title: "Surprise reminders",
                    detail: "Nudge when you're near their spot."
                ),
                BondPlusBenefit(
                    icon: "square.stack.fill",
                    title: "Reminder templates",
                    detail: "Curated prompts so you never blank."
                ),
                BondPlusBenefit(
                    icon: "sparkles",
                    title: "Love-language insights",
                    detail: "See what lands over time."
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
            return "Everything you need to keep showing up for your partner."
        }
        return "Stay close on purpose with the full Bond experience."
    }

    static func trialSubheadline(isSolo: Bool) -> String {
        if isSolo {
            return "Templates, surprise reminders, and insights. No charge until your trial ends."
        }
        return "Daily Check-In, insights, and surprise reminders. No charge until your trial ends."
    }
}
