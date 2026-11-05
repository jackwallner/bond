import SwiftUI

enum PremiumFeature {
    case checkIn, insights, templates

    var gateHeadline: String {
        switch self {
        case .checkIn:    String(localized: "One question, every day.")
        case .insights:   String(localized: "How you tend to each other.")
        case .templates:  String(localized: "Reminder packs, ready to go.")
        }
    }

    var gateSubhead: String {
        switch self {
        case .checkIn:    String(localized: "Both of you answer the same prompt. You see each other's once you've both replied.")
        case .insights:   String(localized: "Track which love languages you're leaning on, and which need attention.")
        case .templates:  String(localized: "Curated sets for date nights, long distance, daily affirmations, and more.")
        }
    }

    var ctaTitle: String { String(localized: "Explore Little Gestures+") }
}

/// Restore button shared by every gate card. Restoring success flips
/// `isPremium`, which dismisses the surrounding gate - so the only thing this
/// has to surface itself is the *failure* case (nothing to restore, or a
/// network error). Without this feedback the button silently stops spinning,
/// which reads as "broken" and is exactly what App Review tends to test.
struct BondRestoreButton: View {
    @Environment(PurchasesService.self) private var purchases
    @State private var isRestoring = false
    @State private var showResult = false

    var body: some View {
        Button {
            Task {
                isRestoring = true
                defer { isRestoring = false }
                await purchases.restore()
                // Success drops the gate; only announce when it didn't unlock.
                if !purchases.isPremium { showResult = true }
            }
        } label: {
            if isRestoring {
                ProgressView()
            } else {
                Text("Restore purchases")
                    .font(.bond(.footnote))
                    .foregroundStyle(.bondTextSecondary)
            }
        }
        .disabled(isRestoring)
        .alert("Restore Purchases", isPresented: $showResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(purchases.lastError
                 ?? String(localized: "No active Little Gestures+ purchase found for this Apple ID."))
        }
    }
}

/// Inline unlock card shown beneath a free preview of a gated feature. One
/// shape for check-in, insights, and templates so the gated screens feel
/// consistent.
struct BondUnlockCard: View {
    let icon: String
    let headline: String
    let subhead: String
    var ctaTitle: String = String(localized: "Explore Little Gestures+")
    @Binding var isPaywallPresented: Bool
    /// Adds outer padding when the card sits in a Form row whose insets have
    /// been zeroed (so it doesn't run edge-to-edge).
    var outerPadding: Bool = false

    var body: some View {
        VStack(spacing: BondSpacing.m) {
            VStack(spacing: BondSpacing.xs) {
                Image(systemName: icon)
                    .font(.bond(.title2))
                    .foregroundStyle(Color.bondAccent)
                Text(headline)
                    .font(.bond(.headline))
                    .multilineTextAlignment(.center)
                Text(subhead)
                    .font(.bond(.subheadline))
                    .foregroundStyle(.bondTextSecondary)
                    .multilineTextAlignment(.center)
            }
            BondPrimaryButton(title: ctaTitle) {
                isPaywallPresented = true
            }
            BondRestoreButton()
        }
        .padding(BondSpacing.base)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: BondRadius.hero))
        .padding(outerPadding ? BondSpacing.base : 0)
    }
}
