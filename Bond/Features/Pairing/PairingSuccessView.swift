import SwiftUI

/// One-time interstitial shown right after pairing completes. It exists for a
/// single beat of weight — no CTA, no upsell, no onboarding.
struct PairingSuccessView: View {
    let partnerName: String?
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0

    var body: some View {
        VStack(spacing: BondSpacing.xl) {
            Spacer()

            CoupleMark(progress: reduceMotion ? 1 : progress)

            VStack(spacing: BondSpacing.s) {
                Text("You're paired.")
                    .font(.bond(.largeTitle, weight: .bold))
                Text(namesLine)
                    .font(.bond(.title3))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Always an explicit Continue — pairing is an emotionally
            // meaningful moment; don't auto-dismiss it out from under the
            // user before they can read the names or screenshot it.
            BondPrimaryButton(title: "Continue", action: onDone)
                .padding(.horizontal, BondSpacing.base)

            Spacer().frame(height: BondSpacing.xxxl)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onDone() }
        .onAppear {
            UIAccessibility.post(notification: .announcement, argument: accessibilityAnnouncement)
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.2)) { progress = 1 }
        }
    }

    private var namesLine: String {
        if let partnerName, !partnerName.isEmpty {
            return "You & \(partnerName)"
        }
        return "You're paired with someone."
    }

    private var accessibilityAnnouncement: String {
        if let partnerName, !partnerName.isEmpty {
            return "You're paired with \(partnerName)."
        }
        return "You're paired."
    }
}

private struct CoupleMark: View {
    /// 0 = hearts apart, 1 = hearts settled together.
    let progress: Double

    var body: some View {
        ZStack {
            Image(systemName: "heart.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.bondAccent.gradient)
                .opacity(progress)
                .scaleEffect(0.6 + 0.4 * progress)

            Image(systemName: "heart.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.bondAccent)
                .offset(x: -40 * (1 - progress) - 8, y: 0)

            Image(systemName: "heart.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.bondAccent.opacity(0.7))
                .offset(x: 40 * (1 - progress) + 8, y: 0)
        }
        .frame(height: 80)
        .accessibilityElement()
        .accessibilityLabel("Paired")
    }
}
