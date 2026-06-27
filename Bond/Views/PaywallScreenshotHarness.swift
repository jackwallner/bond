#if DEBUG
import SwiftUI

struct PaywallScreenshotHarness: View {
    let mode: PaywallScreenshotMode
    @State private var purchases = PurchasesService.shared
    @State private var pairing = PairingService()
    @State private var isReady = false

    var body: some View {
        NavigationStack {
            Group {
                if isReady {
                    if mode == .trial {
                        trialBackdrop {
                            PaywallView(displayCloseButton: true, impressionId: "snapshot_trial")
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
        }
        .task {
            await purchases.bootstrap()
            isReady = true
        }
    }

    private func trialBackdrop<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color.bondSurface.opacity(0.9).ignoresSafeArea()
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
