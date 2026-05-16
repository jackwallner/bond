import RevenueCat
import RevenueCatUI
import SwiftUI

/// Hosted RevenueCat paywall — the offering, products, copy, and pricing
/// are all configured remotely in the RevenueCat dashboard.
struct PaywallView: View {
    @Environment(PurchasesService.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        RevenueCatUI.PaywallView(displayCloseButton: true)
            .onPurchaseCompleted { _ in
                Task { await purchases.refresh() }
                dismiss()
            }
            .onRestoreCompleted { _ in
                Task { await purchases.refresh() }
            }
    }
}
