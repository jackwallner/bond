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
                    offerLabel: trialPackage?.bondIntroOfferLabel,
                    priceLabel: trialPackage?.bondPriceLabel,
                    isPurchasing: isPurchasing,
                    errorMessage: errorMessage,
                    onStartTrial: startTrialPurchase,
                    onSeeAllPlans: { showFullPaywall = true },
                    onDismiss: onClose
                )
            }
        }
        .presentationDetents(showFullPaywall ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
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
                        errorMessage = "Payment went through but we're still syncing. Tap Restore on the next screen."
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
