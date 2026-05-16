import SwiftUI

enum PremiumFeature {
    case checkIn, milestones, insights, templates

    var gateHeadline: String {
        switch self {
        case .checkIn:    "One question, every day."
        case .milestones: "Dates that matter."
        case .insights:   "How you tend to each other."
        case .templates:  "Reminder packs, ready to go."
        }
    }

    var gateSubhead: String {
        switch self {
        case .checkIn:    "Both of you answer the same prompt. You see each other's once you've both replied."
        case .milestones: "Anniversaries, birthdays, the day you moved in. Countdown widgets included."
        case .insights:   "Track which love languages you're leaning on — and which need attention."
        case .templates:  "Curated sets for date nights, long distance, daily affirmations, and more."
        }
    }

    var ctaTitle: String { "Try Premium free for 7 days" }
}

/// Gate shell: shows the real feature rendered with synthetic data behind a
/// soft blur + fade, with a sticky CTA card. Replaces the old takeover
/// PremiumGateView. The preview is never interactive and never real data.
struct BondGatePreview<Preview: View>: View {
    let feature: PremiumFeature
    @Binding var isPaywallPresented: Bool
    @ViewBuilder var preview: () -> Preview

    @Environment(PurchasesService.self) private var purchases
    @State private var isRestoring = false

    var body: some View {
        ZStack(alignment: .bottom) {
            preview()
                .allowsHitTesting(false)
                .blur(radius: 4)
                .accessibilityHidden(true)
                .overlay {
                    LinearGradient(
                        colors: [Color.bondSurface.opacity(0), Color.bondSurface.opacity(0.95)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                }

            VStack(spacing: BondSpacing.s) {
                VStack(spacing: BondSpacing.xs) {
                    Text(feature.gateHeadline).font(.headline)
                    Text(feature.gateSubhead)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                BondPrimaryButton(title: feature.ctaTitle) {
                    isPaywallPresented = true
                }
                Button {
                    Task {
                        isRestoring = true
                        defer { isRestoring = false }
                        await purchases.restore()
                    }
                } label: {
                    if isRestoring {
                        ProgressView()
                    } else {
                        Text("Restore purchases")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(isRestoring)
            }
            .padding(BondSpacing.base)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: BondRadius.hero))
            .padding(BondSpacing.base)
            .accessibilityElement(children: .contain)
        }
    }
}
