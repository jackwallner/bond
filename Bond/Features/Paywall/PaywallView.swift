import RevenueCat
import SwiftUI

/// Legal links required by App Store guideline 3.1.2 adjacent to purchase controls.
enum PaywallLinks {
    static let privacyPolicy = URL(string: "https://jackwallner.github.io/bond/privacy")!
    static let terms = URL(string: "https://jackwallner.github.io/bond/terms")!
}

/// Native Bond+ paywall. Purchases flow through `PurchasesService.purchase`
/// → `Purchases.shared.purchase(package:)` so RevenueCat records transactions,
/// trials, and renewals exactly as with the hosted UI.
///
/// Layout target: fit on a single screen on standard iPhone sizes (no scroll)
/// so the offer + CTA are always visible — scroll adds conversion friction.
struct PaywallView: View {
    @Environment(PurchasesService.self) private var purchases
    @Environment(PairingService.self) private var pairing
    @Environment(\.dismiss) private var dismiss

    /// Prefer this over `dismiss()` when the paywall is hosted in a nested sheet.
    var onClose: (() -> Void)? = nil
    var displayCloseButton = true
    var impressionId = "bond_premium_sheet"

    @State private var selectedPackage: Package?
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var restoreMessage: String?
    @State private var isRestoring = false
    /// Set when a purchase completes at StoreKit but the entitlement hasn't
    /// landed after our retry budget - surfaces a prominent inline Restore
    /// CTA instead of the small one in the legal footer.
    @State private var needsManualRestore = false

    /// True when the buyer has no partner yet. Everyone starts solo (pairing is
    /// opt-in), so the headline couples benefit - Daily Check-In - isn't usable
    /// for them. Leading with it would sell a feature they can't access, which
    /// kills conversion and risks an "advertised feature unavailable" review hit.
    private var isSolo: Bool { pairing.solo || pairing.coupleId == nil }

    /// Concrete Bond+ features framed as outcomes. For paired users we lead with
    /// the daily hook; for solo users we lead with the wins they can use today.
    private var benefits: [BondPlusBenefit] {
        BondPlusBenefits.benefits(isSolo: isSolo)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bondSurface.ignoresSafeArea()

                if purchases.isLoadingProducts && purchases.products.isEmpty {
                    loadingState
                } else if purchases.products.isEmpty {
                    emptyState
                } else {
                    content
                }

            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if displayCloseButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            closePaywall()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Close")
                    }
                }
            }
        }
        .onChange(of: purchases.isPremium) { _, isPremium in
            if isPremium { closePaywall() }
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
        VStack(spacing: BondSpacing.m) {
            header
            benefitList
            planCards
            Spacer(minLength: 0)
            purchaseSection
            legalFooter
        }
        .padding(.horizontal, BondSpacing.xl)
        .padding(.top, displayCloseButton ? BondSpacing.s : BondSpacing.m)
        .padding(.bottom, BondSpacing.base)
        .frame(maxHeight: .infinity)
    }

    private var header: some View {
        VStack(spacing: BondSpacing.xs) {
            Text("Bond+")
                .font(.bond(.title2, weight: .heavy))
                .foregroundStyle(Color.bondAccent.gradient)
            Text(BondPlusBenefits.paywallSubheadline(isSolo: isSolo))
                .font(.bond(.footnote))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
        }
    }

    private var benefitList: some View {
        VStack(alignment: .leading, spacing: BondSpacing.s) {
            ForEach(benefits) { benefit in
                HStack(alignment: .top, spacing: BondSpacing.s) {
                    Image(systemName: benefit.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.bondAccent)
                        .frame(width: 24, height: 24)
                        .background(Color.bondAccent.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(benefit.title)
                            .font(.bond(.subheadline, weight: .semibold))
                            .lineLimit(1)
                        Text(benefit.detail)
                            .font(.bond(.caption))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, BondSpacing.m)
        .padding(.vertical, BondSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var planCards: some View {
        VStack(spacing: BondSpacing.s) {
            ForEach(purchases.products, id: \.identifier) { package in
                BondPlanCard(
                    package: package,
                    isSelected: selectedPackage?.identifier == package.identifier,
                    showsTrialBadge: purchases.isEligibleForIntroOffer(package),
                    isBestValue: package.bondPackageKind == .yearly,
                    savingsPercent: savingsPercentLabel(for: package),
                    perWeekPrice: perWeekLabel(for: package)
                ) {
                    selectedPackage = package
                }
            }
        }
    }

    private var purchaseSection: some View {
        VStack(spacing: BondSpacing.s) {
            BondPrimaryButton(title: ctaTitle, isLoading: isPurchasing) {
                startPurchase()
            }
            .disabled(isPurchasing || selectedPackage == nil)

            if let subline = ctaSubline {
                Text(subline)
                    .font(.bond(.footnote, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(minHeight: 36, alignment: .top)
            } else {
                Text(" ")
                    .font(.bond(.footnote, weight: .semibold))
                    .frame(minHeight: 36)
                    .opacity(0)
                    .accessibilityHidden(true)
            }

            if let statusMessage {
                HStack(spacing: BondSpacing.xs) {
                    ProgressView().controlSize(.small)
                    Text(statusMessage)
                        .font(.bond(.footnote))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.bond(.footnote))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            if needsManualRestore {
                BondPrimaryButton(
                    title: isRestoring ? "Restoring…" : "Restore Purchase",
                    isLoading: isRestoring
                ) {
                    startRestore()
                }
                .disabled(isRestoring)
            }
            if let restoreMessage {
                Text(restoreMessage)
                    .font(.bond(.footnote))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var legalFooter: some View {
        VStack(spacing: BondSpacing.xs) {
            Text(autoRenewDisclosure ?? " ")
                .font(.bond(.caption2))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.9)
                .frame(minHeight: 44, alignment: .top)
                .opacity(autoRenewDisclosure == nil ? 0 : 1)
                .accessibilityHidden(autoRenewDisclosure == nil)

            HStack(spacing: BondSpacing.m) {
                Button {
                    startRestore()
                } label: {
                    Text(isRestoring ? "Restoring…" : "Restore")
                        .font(.bond(.caption2, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .disabled(isRestoring || isPurchasing)

                Text("·").foregroundStyle(.tertiary)
                Link("Terms", destination: PaywallLinks.terms)
                Text("·").foregroundStyle(.tertiary)
                Link("Privacy", destination: PaywallLinks.privacyPolicy)
            }
            .font(.bond(.caption2))
            .foregroundStyle(.tertiary)
        }
    }

    private func closePaywall() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    // MARK: - Derived copy

    private var monthlyPackage: Package? {
        purchases.products.first { $0.bondPackageKind == .monthly }
    }

    private func savingsPercentLabel(for package: Package) -> String? {
        guard package.bondPackageKind == .yearly, let monthly = monthlyPackage else { return nil }
        guard let percent = package.bondSavingsPercent(comparedToMonthly: monthly) else { return nil }
        return "SAVE \(percent)%"
    }

    private func perWeekLabel(for package: Package) -> String? {
        guard package.bondPackageKind == .yearly else { return nil }
        return package.bondPricePerWeekLabel
    }

    private var ctaTitle: String {
        guard let package = selectedPackage else { return "Continue" }
        if package.bondPackageKind == .lifetime { return "Unlock Lifetime" }
        if purchases.isEligibleForIntroOffer(package), let days = package.bondTrialDays {
            return "Start \(days)-Day Free Trial"
        }
        if purchases.isEligibleForIntroOffer(package) { return "Start Free Trial" }
        return "Get Bond+"
    }

    private var ctaSubline: String? {
        guard let package = selectedPackage else { return nil }
        if package.bondPackageKind == .lifetime { return nil }
        let price = package.bondPriceLabel
        if purchases.isEligibleForIntroOffer(package) {
            // "No payment due now" is the single highest-leverage reassurance
            // for trial starts - it answers the exact fear that stops the tap.
            return "No payment due now. Then \(price). Cancel anytime."
        }
        return "\(price). Renews automatically."
    }

    /// Compact auto-renew disclosure (3.1.2) - shown for subscriptions only, not lifetime.
    private var autoRenewDisclosure: String? {
        guard let package = selectedPackage, package.storeProduct.subscriptionPeriod != nil else {
            return nil
        }
        return "Payment charged to your Apple ID. Renews unless cancelled at least 24 hours before period end."
    }

    // MARK: - Actions

    private func selectDefaultPackageIfNeeded() {
        #if DEBUG
        if let mode = PaywallScreenshotMode.current, !purchases.products.isEmpty {
            switch mode {
            case .monthly:
                selectedPackage = purchases.products.first { $0.bondPackageKind == .monthly }
            case .lifetime:
                selectedPackage = purchases.products.first { $0.bondPackageKind == .lifetime }
            case .yearly, .trial:
                selectedPackage = purchases.products.first { $0.bondPackageKind == .yearly }
            }
            return
        }
        #endif
        guard selectedPackage == nil, !purchases.products.isEmpty else { return }
        selectedPackage = purchases.products.first { $0.bondPackageKind == .yearly }
            ?? purchases.products.first
    }

    private func startPurchase() {
        guard let package = selectedPackage else { return }
        errorMessage = nil
        statusMessage = nil
        restoreMessage = nil
        needsManualRestore = false
        isPurchasing = true
        Task {
            defer { isPurchasing = false }
            do {
                switch try await purchases.purchase(package) {
                case .purchased:
                    statusMessage = nil
                    closePaywall()
                case .pending:
                    // Payment cleared but entitlement hasn't propagated yet -
                    // common in sandbox. Show a calm finalizing state; the
                    // `onChange(of: isPremium)` will auto-dismiss as soon as
                    // RevenueCat catches up.
                    statusMessage = "Finalizing your purchase…"
                    await purchases.restore()
                    if purchases.isPremium {
                        statusMessage = nil
                        closePaywall()
                    } else {
                        statusMessage = nil
                        errorMessage = "Your payment went through but we're still syncing it. Tap below to finish unlocking."
                        needsManualRestore = true
                    }
                case .cancelled:
                    statusMessage = nil
                }
            } catch {
                statusMessage = nil
                // Prefer the message PurchasesService just set (it maps
                // RC ErrorCodes to actionable copy); fall back to the
                // raw description so we never swallow a real error.
                errorMessage = purchases.lastError ?? error.localizedDescription
                // Only surface the prominent Restore CTA when the failure looks
                // like a purchase that may already exist on this Apple ID.
                // For plain failures (network, store outage) there's nothing to
                // restore, so a Restore button would only confuse.
                needsManualRestore = purchases.lastErrorSuggestsRestore
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
            if purchases.isPremium {
                needsManualRestore = false
            } else {
                restoreMessage = purchases.lastError
                    ?? "No active Bond+ purchase found for this Apple ID."
            }
        }
    }
}

// MARK: - Plan Card

private struct BondPlanCard: View {
    let package: Package
    let isSelected: Bool
    let showsTrialBadge: Bool
    let isBestValue: Bool
    let savingsPercent: String?
    let perWeekPrice: String?
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
                        if let savingsPercent {
                            Text(savingsPercent)
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.bondAccent, in: Capsule())
                        } else if isBestValue {
                            Text("BEST VALUE")
                                .font(.system(size: 9, weight: .heavy))
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
                    } else if let perWeekPrice {
                        Text("Just \(perWeekPrice)")
                            .font(.bond(.caption2, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: BondSpacing.s)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(package.bondPriceLabel)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                    if showsTrialBadge, let perWeekPrice {
                        Text(perWeekPrice)
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, BondSpacing.base)
            .padding(.vertical, BondSpacing.s)
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
