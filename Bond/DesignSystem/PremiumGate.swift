import SwiftUI

enum PremiumFeature {
    case checkIn, insights, templates

    var gateHeadline: String {
        switch self {
        case .checkIn:    "One question, every day."
        case .insights:   "How you tend to each other."
        case .templates:  "Reminder packs, ready to go."
        }
    }

    var gateSubhead: String {
        switch self {
        case .checkIn:    "Both of you answer the same prompt. You see each other's once you've both replied."
        case .insights:   "Track which love languages you're leaning on, and which need attention."
        case .templates:  "Curated sets for date nights, long distance, daily affirmations, and more."
        }
    }

    var ctaTitle: String { "Try Bond+ free" }
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
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(isRestoring)
        .alert("Restore Purchases", isPresented: $showResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(purchases.lastError
                 ?? "No active Bond+ purchase found for this Apple ID.")
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
    var ctaTitle: String = "Try Bond+ free"
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
                    .foregroundStyle(.secondary)
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
