import SwiftUI

struct PreferenceChoiceView: View {
    @Environment(PairingService.self) private var pairing
    @State private var isCreatingSolo = false

    var body: some View {
        VStack(alignment: .leading, spacing: BondSpacing.xl) {
            Spacer()

            BondScreenHeader(title: "How will you use Bond?")
                .padding(.horizontal, BondSpacing.base)

            VStack(spacing: BondSpacing.m) {
                BondChoiceCard(
                    symbol: "person.fill",
                    title: "Just me",
                    description: "Reminders for yourself. Journaling, habits, the things you keep meaning to do.",
                    tint: .secondary
                ) {
                    Task {
                        isCreatingSolo = true
                        defer { isCreatingSolo = false }
                        await pairing.createSoloCouple()
                    }
                }
                .disabled(isCreatingSolo)

                BondChoiceCard(
                    symbol: "heart.fill",
                    title: "With someone",
                    description: "Share reminders with your partner. Little nudges, surprises, milestones together.",
                    tint: .bondAccent
                ) {
                    pairing.needsPreferenceChoice = false
                }
                .disabled(isCreatingSolo)
            }
            .padding(.horizontal, BondSpacing.base)

            if let error = pairing.lastError {
                BondInlineError(message: error)
            }

            Text("You can switch later in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)

            Spacer()
        }
        .padding(.vertical, BondSpacing.xxxl)
    }
}
