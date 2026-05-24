import RevenueCat
import SwiftUI

/// Legal links required by App Store guideline 3.1.2 adjacent to purchase controls.
enum PaywallLinks {
    static let privacyPolicy = URL(string: "https://jackwallner.com/bond/privacy")!
    static let terms = URL(string: "https://jackwallner.com/bond/terms")!
    static let standardEULA = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

/// Native Bond Premium paywall. Purchases flow through `PurchasesService.purchase`
/// → `Purchases.shared.purchase(package:)` so RevenueCat records transactions,
/// trials, and renewals exactly as with the hosted UI.
struct PaywallView: View {
    @Environment(PurchasesService.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    var displayCloseButton = true
    var impressionId = "bond_premium_sheet"

    @State private var selectedPackage: Package?
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var restoreMessage: String?
    @State private var isRestoring = false

    private let features: [(icon: String, title: String)] = [
        ("questionmark.bubble.fill", "Daily Check-In: answer together, reveal when you've both replied"),
        ("chart.bar.xaxis.ascending", "Insights: love-language balance and weekly trends"),
        ("bell.badge.fill", "Premium triggers: location and surprise reminders"),
        ("square.stack.fill", "Reminder template packs for date nights, long distance, and more")
    ]

    var body: some View {
        ZStack {
            Color.bondSurface.ignoresSafeArea()

            if purchases.isLoadingProducts && purchases.products.isEmpty {
                loadingState
            } else if purchases.products.isEmpty {
                emptyState
            } else {
                content
            }

            if displayCloseButton {
                closeButton
            }
        }
        .onChange(of: purchases.isPremium) { _, isPremium in
            if isPremium { dismiss() }
        }
        .task {
            purchases.trackPaywallImpression(id: impressionId)
            if purchases.products.isEmpty {
                await purchases.fetchProducts()
            }
            selectDefaultPackageIfNeeded()
        }
        .onChange(of: purchases.products.count) { _, _ in
            selectDefaultPackageIfNeeded()
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: BondSpacing.m) {
            ProgressView()
                .controlSize(.large)
            Text("Loading plans…")
                .font(.bond(.subheadline))
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: BondSpacing.m) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Couldn't Load Plans")
                .font(.bond(.headline))
            Text(purchases.lastError ?? "Check your connection and try again.")
                .font(.bond(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BondSpacing.xl)
            Button("Try Again") {
                Task {
                    await purchases.fetchProducts()
                    selectDefaultPackageIfNeeded()
                }
            }
            .font(.bond(.subheadline, weight: .semibold))
            .foregroundStyle(Color.bondAccent)
        }
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: BondSpacing.xl) {
                header
                featureList
                planCards
                purchaseSection
            }
            .padding(.horizontal, BondSpacing.xl)
            .padding(.top, displayCloseButton ? 56 : BondSpacing.xxl)
            .padding(.bottom, BondSpacing.xxl)
        }
    }

    private var header: some View {
        VStack(spacing: BondSpacing.s) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.bondAccent.gradient)
            Text("Bond Premium")
                .font(.bond(.title, weight: .bold))
            Text("Stay tuned to each other, without the noise.")
                .font(.bond(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: BondSpacing.m) {
            ForEach(features, id: \.title) { feature in
                HStack(alignment: .top, spacing: BondSpacing.m) {
                    Image(systemName: feature.icon)
                        .font(.bond(.body, weight: .semibold))
                        .foregroundStyle(Color.bondAccent)
                        .frame(width: 24)
                    Text(feature.title)
                        .font(.bond(.subheadline))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var planCards: some View {
        VStack(spacing: BondSpacing.s) {
            ForEach(purchases.products, id: \.identifier) { package in
                BondPlanCard(
                    package: package,
                    isSelected: selectedPackage?.identifier == package.identifier,
                    showsTrialBadge: purchases.isEligibleForIntroOffer(package),
                    isBestValue: package.bondPackageKind == .yearly
                ) {
                    selectedPackage = package
                }
            }
        }
    }

    private var purchaseSection: some View {
        VStack(spacing: BondSpacing.m) {
            BondPrimaryButton(title: ctaTitle, isLoading: isPurchasing) {
                startPurchase()
            }
            .disabled(isPurchasing || selectedPackage == nil)

            if let disclosure = disclosureText {
                Text(disclosure)
                    .font(.bond(.caption))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.bond(.footnote))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            if let restoreMessage {
                Text(restoreMessage)
                    .font(.bond(.footnote))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                startRestore()
            } label: {
                Text(isRestoring ? "Restoring…" : "Restore Purchases")
                    .font(.bond(.subheadline, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isRestoring || isPurchasing)

            HStack(spacing: 4) {
                Link("Terms", destination: PaywallLinks.standardEULA)
                Text("·")
                Link("Privacy", destination: PaywallLinks.privacyPolicy)
            }
            .font(.bond(.caption2))
            .foregroundStyle(.tertiary)
        }
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                        .padding(BondSpacing.base)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Copy

    private var ctaTitle: String {
        guard let package = selectedPackage else { return "Continue" }
        if package.bondPackageKind == .lifetime { return "Unlock Lifetime" }
        if purchases.isEligibleForIntroOffer(package) { return "Start Free Trial" }
        return "Subscribe"
    }

    private var disclosureText: String? {
        guard let package = selectedPackage else { return nil }
        let price = package.bondPriceLabel
        let renew = "Auto-renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel in Settings."
        if package.bondPackageKind == .lifetime {
            return "\(price). One-time purchase. Lifetime access, no subscription."
        }
        if purchases.isEligibleForIntroOffer(package), let trial = package.bondIntroOfferLabel {
            return "\(trial.capitalized), then \(price). \(renew)"
        }
        return "\(price). \(renew)"
    }

    // MARK: - Actions

    private func selectDefaultPackageIfNeeded() {
        guard selectedPackage == nil, !purchases.products.isEmpty else { return }
        selectedPackage = purchases.products.first { $0.bondPackageKind == .yearly }
            ?? purchases.products.first
    }

    private func startPurchase() {
        guard let package = selectedPackage else { return }
        errorMessage = nil
        restoreMessage = nil
        isPurchasing = true
        Task {
            defer { isPurchasing = false }
            do {
                switch try await purchases.purchase(package) {
                case .purchased, .pending:
                    break
                case .cancelled:
                    errorMessage = "Purchase cancelled. Tap again to continue."
                }
            } catch {
                errorMessage = "Couldn't complete the purchase. Please try again."
            }
        }
    }

    private func startRestore() {
        errorMessage = nil
        restoreMessage = nil
        isRestoring = true
        Task {
            defer { isRestoring = false }
            await purchases.restore()
            if !purchases.isPremium {
                restoreMessage = purchases.lastError
                    ?? "No active Bond Premium purchase found for this Apple ID."
            }
        }
    }
}

private struct BondPlanCard: View {
    let package: Package
    let isSelected: Bool
    let showsTrialBadge: Bool
    let isBestValue: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: BondSpacing.m) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.bondAccent : Color.secondary.opacity(0.35), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(Color.bondAccent)
                            .frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: BondSpacing.xs) {
                        Text(package.bondDisplayName)
                            .font(.bond(.subheadline, weight: .bold))
                        if isBestValue {
                            Text("BEST VALUE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.bondAccent, in: Capsule())
                        }
                    }
                    if showsTrialBadge, let trial = package.bondIntroOfferLabel {
                        Text(trial.capitalized)
                            .font(.bond(.caption2, weight: .semibold))
                            .foregroundStyle(Color.bondAccent)
                    }
                }

                Spacer(minLength: BondSpacing.s)

                Text(package.bondPriceLabel)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, BondSpacing.base)
            .padding(.vertical, BondSpacing.m)
            .background(Color.bondCardFill, in: RoundedRectangle(cornerRadius: BondRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BondRadius.card, style: .continuous)
                    .stroke(isSelected ? Color.bondAccent : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .bondSoftElevation(radius: BondRadius.card)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
