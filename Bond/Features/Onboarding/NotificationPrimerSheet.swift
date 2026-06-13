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
    let onRequest: () -> Void

    var body: some View {
        VStack(spacing: BondSpacing.xl) {
            Spacer().frame(height: BondSpacing.xl)

            Image(systemName: "bell")
                .font(.system(size: 48))
                .foregroundStyle(Color.bondAccent)
                .accessibilityHidden(true)

            VStack(spacing: BondSpacing.m) {
                Text("Bond is silent without your permission.")
                    .font(.bond(.title2, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("Reminders fire as notifications. No notifications, no reminders. That's the whole app.")
                    .font(.bond(.body))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, BondSpacing.l)

            Spacer()

            VStack(spacing: BondSpacing.s) {
                BondPrimaryButton(title: "Turn on notifications") {
                    onRequest()
                    dismiss()
                }
                Button("Maybe later") { dismiss() }
                    .font(.bond(.footnote))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, BondSpacing.s)
            }
            .padding(.horizontal, BondSpacing.base)
        }
        .padding(.top, BondSpacing.l)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
