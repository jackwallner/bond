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
///
/// Layout follows high-converting patterns from comparable couples / habit apps
/// (Paired, Lasting, Cal AI): outcome-led hero, four-bullet value list,
/// trial-timeline reassurance, plan picker pre-selected on annual with per-week
/// price + savings badge, single primary CTA with renewal disclosure beneath.
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

    /// Outcome-led bullets. Order matters: lead with the daily-use hook that
    /// most users will pull the app open for, then the differentiating
    /// insight feature, then the two reminder-flavoured features.
    private let benefits: [(icon: String, title: String, detail: String)] = [
        ("questionmark.bubble.fill",
         "Daily Check-In, together",
         "One small question a day. You both answer, then it reveals — no scoreboard."),
        ("sparkles",
         "See what makes them feel loved",
         "Insights track your love-language balance and weekly trends, so you stop guessing."),
        ("bell.badge.fill",
         "Never forget the moments that matter",
         "Smart, location and surprise reminders nudge you at the right time, not the wrong one."),
        ("square.stack.fill",
         "Templates for the hard days",
         "Date night, long-distance, post-fight repair — curated prompts you can send in two taps.")
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
                benefitList
                trialTimelineIfApplicable
                planCards
                purchaseSection
                legalFooter
            }
            .padding(.horizontal, BondSpacing.xl)
            .padding(.top, displayCloseButton ? 56 : BondSpacing.xxl)
            .padding(.bottom, BondSpacing.xxl)
        }
    }

    private var header: some View {
        VStack(spacing: BondSpacing.s) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.bondAccent.gradient)
                .padding(.bottom, BondSpacing.xs)
            Text("Stay close, on purpose.")
                .font(.bond(.title, weight: .bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Bond Premium is the small daily nudge that keeps the two of you tuned in — without making it a chore.")
                .font(.bond(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var benefitList: some View {
        VStack(alignment: .leading, spacing: BondSpacing.m) {
            ForEach(benefits, id: \.title) { benefit in
                HStack(alignment: .top, spacing: BondSpacing.m) {
                    Image(systemName: benefit.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.bondAccent)
                        .frame(width: 28, height: 28)
                        .background(Color.bondAccent.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(benefit.title)
                            .font(.bond(.subheadline, weight: .semibold))
                        Text(benefit.detail)
                            .font(.bond(.footnote))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var trialTimelineIfApplicable: some View {
        if let days = trialDaysForTimeline {
            BondTrialTimeline(totalDays: days)
        }
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
        VStack(spacing: BondSpacing.m) {
            BondPrimaryButton(title: ctaTitle, isLoading: isPurchasing) {
                startPurchase()
            }
            .disabled(isPurchasing || selectedPackage == nil)

            if let subline = ctaSubline {
                Text(subline)
                    .font(.bond(.footnote, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
        }
    }

    private var legalFooter: some View {
        VStack(spacing: BondSpacing.s) {
            Button {
                startRestore()
            } label: {
                Text(isRestoring ? "Restoring…" : "Restore Purchases")
                    .font(.bond(.footnote, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isRestoring || isPurchasing)

            HStack(spacing: BondSpacing.s) {
                Link("Terms", destination: PaywallLinks.standardEULA)
                Text("·").foregroundStyle(.tertiary)
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

    // MARK: - Derived copy

    private var trialDaysForTimeline: Int? {
        let yearly = purchases.products.first { $0.bondPackageKind == .yearly }
        let candidate = yearly ?? selectedPackage ?? purchases.products.first
        guard let candidate, purchases.isEligibleForIntroOffer(candidate) else { return nil }
        return candidate.bondTrialDays
    }

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
        return "Subscribe"
    }

    private var ctaSubline: String? {
        guard let package = selectedPackage else { return nil }
        if package.bondPackageKind == .lifetime { return nil }
        let price = package.bondPriceLabel
        if purchases.isEligibleForIntroOffer(package) {
            return "Then \(price). Cancel anytime."
        }
        return "Cancel anytime."
    }

    private var disclosureText: String? {
        guard let package = selectedPackage else { return nil }
        let price = package.bondPriceLabel
        let renew = "Auto-renews unless cancelled at least 24 hours before the end of the period. Manage or cancel in Settings."
        if package.bondPackageKind == .lifetime {
            return "\(price). One-time purchase. No subscription."
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

// MARK: - Trial Timeline

/// Three-step reassurance graphic shown when the default package has a free
/// trial. Matches the "How your free trial works" pattern used by Paired,
/// Lasting, Calm — defuses subscription anxiety, which is the #1 cause of
/// trial-flow drop-off.
private struct BondTrialTimeline: View {
    let totalDays: Int

    var body: some View {
        VStack(alignment: .leading, spacing: BondSpacing.m) {
            Text("How your free trial works")
                .font(.bond(.subheadline, weight: .semibold))

            VStack(spacing: 0) {
                step(
                    icon: "lock.open.fill",
                    title: "Today",
                    detail: "Get full access to every Premium feature."
                )
                connector
                step(
                    icon: "bell.fill",
                    title: "Day \(max(totalDays - 2, 1))",
                    detail: "We'll remind you before your trial ends — no surprise charges."
                )
                connector
                step(
                    icon: "checkmark.seal.fill",
                    title: "Day \(totalDays)",
                    detail: "Your subscription begins. Cancel anytime from Settings."
                )
            }
        }
        .padding(BondSpacing.base)
        .background(Color.bondCardFill, in: RoundedRectangle(cornerRadius: BondRadius.card, style: .continuous))
        .bondSoftElevation(radius: BondRadius.card)
    }

    private func step(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: BondSpacing.m) {
            ZStack {
                Circle()
                    .fill(Color.bondAccent.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.bondAccent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.bond(.footnote, weight: .bold))
                Text(detail)
                    .font(.bond(.footnote))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var connector: some View {
        Rectangle()
            .fill(Color.bondAccent.opacity(0.2))
            .frame(width: 2, height: 14)
            .padding(.leading, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
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

                VStack(alignment: .leading, spacing: 4) {
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
