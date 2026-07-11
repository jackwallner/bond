import SwiftUI

/// Final solo-onboarding step: a one-tap Bond+ free-trial offer that reads like
/// another IntentSetup page (same warm cream chrome, same header voice, same
/// bottom CTA slot) rather than a bolted-on paywall sheet.
///
/// This view renders only the page *content* (header + benefit rows). The CTA
/// stack (soft "Get Started" exit, disclosure, primary trial button, and the
/// legal footer) lives in `IntentSetupView` so the primary button frame is
/// pixel-identical to the Continue / "Start using Bond" button on the prior
/// steps - the user's thumb never moves between the last two taps.
struct OnboardingTrialView: View {
    let displayName: String

    private var benefits: [BondPlusBenefit] {
        Array(BondPlusBenefits.benefits(isSolo: true).prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BondSpacing.xl) {
            BondScreenHeader(
                title: "Keep showing up for \(displayName).",
                subtitle: "Bond+ has everything you need to make it a habit. Start with a free trial, cancel anytime."
            )
            .padding(.horizontal, BondSpacing.base)

            VStack(spacing: BondSpacing.s) {
                ForEach(benefits) { benefit in
                    HStack(alignment: .top, spacing: BondSpacing.m) {
                        Image(systemName: benefit.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.bondAccent)
                            .frame(width: 32, height: 32)
                            .background(Color.bondAccent.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(benefit.title)
                                .font(.bond(.subheadline, weight: .semibold))
                            Text(benefit.detail)
                                .font(.bond(.caption))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(BondSpacing.base)
                    .background(Color.bondCardFill, in: RoundedRectangle(cornerRadius: BondRadius.inline))
                }
            }
            .padding(.horizontal, BondSpacing.base)
        }
    }
}
