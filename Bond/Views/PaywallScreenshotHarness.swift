#if DEBUG
import SwiftUI
@preconcurrency import RevenueCat

struct PaywallScreenshotHarness: View {
    let mode: PaywallScreenshotMode
    @State private var purchases = PurchasesService.shared
    @State private var pairing = PairingService()
    @State private var isReady = false

    private var isSolo: Bool { pairing.solo || pairing.coupleId == nil }

    private var trialPackage: Package? {
        purchases.products.first { $0.bondPackageKind == .yearly } ?? purchases.products.first
    }

    var body: some View {
        Group {
            if isReady {
                if mode == .trial {
                    trialBackdrop {
                        TrialOfferSheet(
                            isSolo: isSolo,
                            offerLabel: trialPackage?.bondIntroOfferLabel ?? "7-day free trial",
                            priceLabel: trialPackage?.bondPriceLabel ?? "$29.99 / year",
                            isPurchasing: false,
                            errorMessage: nil,
                            onStartTrial: {},
                            onSeeAllPlans: {},
                            onDismiss: {}
                        )
                    }
                } else {
                    PaywallView(displayCloseButton: false, impressionId: "snapshot")
                }
            } else {
                ProgressView("Loading plans…")
                    .controlSize(.large)
            }
        }
        .environment(purchases)
        .environment(pairing)
        .onAppear { isReady = true }
        .task {
            if purchases.products.isEmpty {
                await purchases.bootstrap()
            }
        }
    }

    private func trialBackdrop<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color.bondSurface.ignoresSafeArea()
            Color.black.opacity(0.12).ignoresSafeArea()
            VStack {
                Spacer()
                content()
                    .frame(maxHeight: UIScreen.main.bounds.height * 0.68)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
            }
        }
    }
}
#endif
