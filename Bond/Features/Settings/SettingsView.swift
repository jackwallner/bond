import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(SupabaseService.self) private var supabase
    @Environment(PurchasesService.self) private var purchases
    @Environment(PairingService.self) private var pairing

    @State private var confirmSignOut = false
    @State private var confirmUnpair = false
    @State private var isRestoring = false
    @State private var isPairingPresented = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            Section("Account") {
                Button("Sign out", role: .destructive) { confirmSignOut = true }
            }

            Section("Pairing") {
                if pairing.solo || pairing.coupleId == nil {
                    Button {
                        isPairingPresented = true
                    } label: {
                        Label("Connect a partner", systemImage: "heart.circle")
                    }
                    Text("Bond is just for you right now. Pair to share reminders — you keep everything you've already added.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: BondSpacing.m) {
                        InitialsAvatar(name: pairing.partnerProfile?.displayName)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pairing.partnerProfile?.displayName ?? "Your partner")
                                .font(.headline)
                            Text("Paired")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("Unpair", role: .destructive) { confirmUnpair = true }
                }
            }

            Section("Premium") {
                if purchases.isPremium {
                    if let since = purchases.premiumSince {
                        LabeledContent("Status") {
                            Text("Premium since \(since.formatted(date: .long, time: .omitted))")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                    } else {
                        LabeledContent("Status", value: "Premium")
                    }
                    Link("Manage subscription",
                         destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                } else {
                    LabeledContent("Status", value: "Free")
                }
                Button {
                    Task {
                        isRestoring = true
                        defer { isRestoring = false }
                        await purchases.restore()
                    }
                } label: {
                    if isRestoring { ProgressView() } else { Text("Restore purchases") }
                }
                .disabled(isRestoring)
            }

            Section("Notifications") {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: notificationStatus == .denied ? "bell.slash" : "bell")
                            .foregroundStyle(notificationStatus == .denied ? .orange : .secondary)
                        Text(notificationStateLabel)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.forward.square")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Link("Privacy policy", destination: URL(string: "https://jackwallner.com/bond/privacy")!)
                Link("Terms of service", destination: URL(string: "https://jackwallner.com/bond/terms")!)
                Link("Support", destination: URL(string: "mailto:bond@jackwallner.com")!)
            } footer: {
                HStack {
                    Spacer()
                    Text("Version \(appVersion) (build \(appBuild))")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            notificationStatus = await UNUserNotificationCenter.current()
                .notificationSettings().authorizationStatus
        }
        .sheet(isPresented: $isPairingPresented) {
            PairingView()
        }
        .onChange(of: pairing.justPaired) { _, paired in
            if paired { isPairingPresented = false }
        }
        .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                Task {
                    await purchases.signOut()
                    await supabase.signOut()
                    pairing.reset()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to sign in again to use Bond.")
        }
        .confirmationDialog("Unpair?", isPresented: $confirmUnpair, titleVisibility: .visible) {
            Button("Unpair", role: .destructive) {
                Task { await pairing.leaveCouple() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll keep your reminders. Your partner will keep theirs.")
        }
    }

    private var notificationStateLabel: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: "On"
        case .denied: "Off — Open Settings"
        default: "Not yet enabled"
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}

private struct InitialsAvatar: View {
    let name: String?

    private var initials: String {
        guard let name, !name.isEmpty else { return "?" }
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    var body: some View {
        Text(initials)
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(Color.bondAccent, in: Circle())
            .accessibilityHidden(true)
    }
}
