import RevenueCat
import SwiftUI

/// Trial sheet first, full plan picker on demand. Used for feature gates and
/// proactive offers so the first touch is a compact sheet, not a full-screen paywall.
struct PaywallFlowSheet: View {
    @Environment(PurchasesService.self) private var purchases
    @Environment(PairingService.self) private var pairing

    let impressionId: String
    var onClose: () -> Void

    @State private var showFullPaywall = false
    @State private var isPurchasing = false
    @State private var errorMessage: String?

    private var isSolo: Bool { pairing.solo || pairing.coupleId == nil }

    private var trialPackage: Package? {
        purchases.products.first { $0.bondPackageKind == .yearly } ?? purchases.products.first
    }

    var body: some View {
        Group {
            if showFullPaywall {
                PaywallView(
                    onClose: onClose,
                    displayCloseButton: true,
                    impressionId: "\(impressionId)_plans"
                )
            } else {
                TrialOfferSheet(
                    isSolo: isSolo,
                    trialPeriodPhrase: trialPackage.flatMap { purchases.isEligibleForIntroOffer($0) ? $0.bondTrialPeriodPhrase : nil },
                    priceLabel: trialPackage?.bondPriceLabel,
                    isPurchasing: isPurchasing,
                    errorMessage: errorMessage,
                    onStartTrial: startTrialPurchase,
                    onSeeAllPlans: { showFullPaywall = true },
                    onDismiss: onClose
                )
            }
        }
        .modifier(PaywallSheetPresentation(showFullPaywall: showFullPaywall))
        .task {
            if purchases.products.isEmpty {
                await purchases.fetchProducts()
            }
            purchases.trackPaywallImpression(id: impressionId)
            if let trialPackage,
               !purchases.isEligibleForIntroOffer(trialPackage) {
                showFullPaywall = true
            } else if trialPackage == nil, !purchases.products.isEmpty {
                showFullPaywall = true
            }
        }
    }

    private func startTrialPurchase() {
        guard let package = trialPackage else {
            showFullPaywall = true
            return
        }
        errorMessage = nil
        isPurchasing = true
        Task {
            defer { isPurchasing = false }
            do {
                switch try await purchases.purchase(package) {
                case .purchased:
                    onClose()
                case .pending:
                    await purchases.restore()
                    if purchases.isPremium { onClose() }
                    else {
                        errorMessage = String(localized: "Payment went through but we're still syncing. Tap Restore on the next screen.")
                        showFullPaywall = true
                    }
                case .cancelled:
                    break
                }
            } catch {
                errorMessage = purchases.lastError ?? error.localizedDescription
                if purchases.lastErrorSuggestsRestore {
                    showFullPaywall = true
                }
            }
        }
    }
}


/// Phones show the offer as a half sheet. iPad shows it as a centred form sheet
/// that keeps its own proportions, and the full plans as a large one.
struct PaywallSheetPresentation: ViewModifier {
    let showFullPaywall: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            if showFullPaywall {
                content
                    .presentationSizing(.page)
                    .presentationDragIndicator(.visible)
            } else {
                content
                    .presentationSizing(.fitted)
                    .presentationDragIndicator(.visible)
            }
        } else {
            content
                .presentationDetents(showFullPaywall ? [.large] : [.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}
