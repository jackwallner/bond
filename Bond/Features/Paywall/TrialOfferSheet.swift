import RevenueCat
import SwiftUI

/// Compact trial pitch shown as a medium sheet before the full plan picker.
struct TrialOfferSheet: View {
    let isSolo: Bool
    let offerLabel: String?
    let priceLabel: String?
    let isPurchasing: Bool
    let errorMessage: String?
    let onStartTrial: () -> Void
    let onSeeAllPlans: () -> Void
    let onDismiss: () -> Void

    private var trialPeriodPhrase: String? {
        guard let offerLabel else { return nil }
        let scanner = Scanner(string: offerLabel)
        var value = 0
        guard scanner.scanInt(&value) else { return nil }
        _ = scanner.scanString("-")
        guard let unit = scanner.scanCharacters(from: .letters) else { return nil }
        let plural = value == 1 ? unit : "\(unit)s"
        return "\(value) \(plural)"
    }

    private var headline: String {
        if let period = trialPeriodPhrase {
            return "\(period) of Bond+, free."
        }
        return "Try Bond+ free."
    }

    private var subheadline: String {
        if trialPeriodPhrase != nil {
            return BondPlusBenefits.trialSubheadline(isSolo: isSolo)
        }
        return BondPlusBenefits.trialSubheadline(isSolo: isSolo)
    }

    private var trialBullets: [BondPlusBenefit] {
        Array(BondPlusBenefits.benefits(isSolo: isSolo).prefix(2))
    }

    private var billingDisclosure: String? {
        guard let priceLabel else { return nil }
        if let period = trialPeriodPhrase {
            return "Free for \(period), then \(priceLabel). Auto-renews unless cancelled 24h before trial ends."
        }
        return "Then \(priceLabel). Auto-renews unless cancelled 24h before trial ends."
    }

    var body: some View {
        VStack(spacing: BondSpacing.m) {
            VStack(spacing: BondSpacing.xs) {
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.bondAccent.gradient, in: Circle())

                Text(headline)
                    .font(.bond(.title3, weight: .bold))
                    .foregroundStyle(Color.bondAccent)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Text(subheadline)
                    .font(.bond(.footnote))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: BondSpacing.s) {
                ForEach(trialBullets) { benefit in
                    HStack(alignment: .top, spacing: BondSpacing.s) {
                        Image(systemName: benefit.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.bondAccent)
                            .frame(width: 28, height: 28)
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
                    .padding(.horizontal, BondSpacing.s)
                    .padding(.vertical, BondSpacing.xs)
                    .background(Color.bondCardFill, in: RoundedRectangle(cornerRadius: BondRadius.card))
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.bond(.footnote))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, BondSpacing.xl)
        .padding(.top, BondSpacing.m)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: BondSpacing.s) {
                if let billingDisclosure {
                    Text(billingDisclosure)
                        .font(.bond(.caption2))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.9)
                }

                BondPrimaryButton(
                    title: trialCTATitle,
                    isLoading: isPurchasing,
                    action: onStartTrial
                )
                .disabled(isPurchasing)

                Button(action: onSeeAllPlans) {
                    Text("See all plans")
                        .font(.bond(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.bondAccent)
                }
                .buttonStyle(.plain)
                .disabled(isPurchasing)

                Button(action: onDismiss) {
                    Text("Not now")
                        .font(.bond(.subheadline, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isPurchasing)

                HStack(spacing: BondSpacing.xs) {
                    Link("Terms", destination: PaywallLinks.terms)
                    Text("·").foregroundStyle(.tertiary)
                    Link("Privacy", destination: PaywallLinks.privacyPolicy)
                }
                .font(.bond(.caption2))
                .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, BondSpacing.xl)
            .padding(.bottom, BondSpacing.base)
            .background(Color.bondSurface)
        }
        .background(Color.bondSurface)
    }

    private var trialCTATitle: String {
        if let days = trialPeriodPhrase?.split(separator: " ").first,
           let dayCount = Int(days) {
            return "Start \(dayCount)-Day Free Trial"
        }
        return "Start My Free Trial"
    }
}
