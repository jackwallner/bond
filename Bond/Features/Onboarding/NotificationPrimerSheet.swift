import SwiftUI

extension Notification.Name {
    /// Posted once the notification-primer question is fully resolved for this
    /// launch - it won't show, the user dismissed it, or the system permission
    /// dialog has been answered. Lets RootView queue follow-up presentations
    /// (the post-onboarding paywall) without racing the primer's sheet.
    static let bondNotificationPrimerResolved =
        Notification.Name("com.jackwallner.bond.notificationPrimerResolved")
}

/// Pre-prompt primer shown once before the system notification dialog.
/// Presented as a medium sheet - never a takeover, always escapable.
struct NotificationPrimerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    let onRequest: () -> Void

    var body: some View {
        // Scrolls when the text outgrows the sheet (large type), so no line or
        // button label is cut; the spacers still pin the button low otherwise.
        GeometryReader { proxy in
            ScrollView {
                content.frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.top, BondSpacing.l)
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium])
        .presentationDragIndicator(.visible)
    }

    private var content: some View {
        VStack(spacing: BondSpacing.xl) {
            Spacer().frame(height: BondSpacing.xl)

            Image(systemName: "bell")
                .font(.system(size: 48))
                .foregroundStyle(Color.bondAccent)
                .accessibilityHidden(true)

            VStack(spacing: BondSpacing.m) {
                Text("Little Gestures is silent without your permission.")
                    .font(.bond(.title2, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("Reminders fire as notifications. No notifications, no reminders. That's the whole app.")
                    .font(.bond(.body))
                    .foregroundStyle(.bondTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, BondSpacing.l)

            Spacer()

            VStack(spacing: BondSpacing.s) {
                BondPrimaryButton(title: String(localized: "Turn on notifications")) {
                    onRequest()
                    dismiss()
                }
                Button("Maybe later") { dismiss() }
                    .font(.bond(.footnote))
                    .foregroundStyle(.bondTextSecondary)
                    .padding(.bottom, BondSpacing.s)
            }
            .padding(.horizontal, BondSpacing.base)
        }
    }
}
