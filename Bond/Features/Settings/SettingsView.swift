import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(SupabaseService.self) private var supabase
    @Environment(PurchasesService.self) private var purchases
    @Environment(PairingService.self) private var pairing
    @State private var theme = BondTheme.shared

    @State private var confirmSignOut = false
    @State private var confirmUnpair = false
    @State private var confirmDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var isRestoring = false
    @State private var showRestoreResult = false
    @State private var isPairingPresented = false
    @State private var isPaywallPresented = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            Section {
                if !supabase.isAnonymous {
                    Button("Sign out", role: .destructive) { confirmSignOut = true }
                }
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    if isDeleting {
                        HStack(spacing: BondSpacing.s) {
                            ProgressView()
                            Text("Deleting…")
                        }
                    } else {
                        Text("Delete account")
                    }
                }
                .disabled(isDeleting)
                if let deleteError {
                    Text(deleteError)
                        .font(.bond(.footnote))
                        .foregroundStyle(.red)
                }
            } header: {
                BondSectionHeader(title: "Account")
            }
            .bondWarmRow()

            Section {
                if pairing.solo || pairing.coupleId == nil {
                    Button {
                        isPairingPresented = true
                    } label: {
                        Label("Connect a partner", systemImage: "heart.circle")
                    }
                    Text("Bond is just for you right now. Pair to share reminders. You keep everything you've already added.")
                        .font(.bond(.caption))
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: BondSpacing.m) {
                        InitialsAvatar(name: pairing.partnerProfile?.displayName)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pairing.partnerProfile?.displayName ?? "Your partner")
                                .font(.bond(.headline))
                            Text("Paired")
                                .font(.bond(.caption))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("Unpair", role: .destructive) { confirmUnpair = true }
                    Link(destination: URL(string: "mailto:jackwallner+b@gmail.com?subject=Report%20a%20concern%20about%20my%20Bond%20partner")!) {
                        Label("Report a concern", systemImage: "exclamationmark.bubble")
                    }
                    Text("Unpairing immediately stops your partner from sending you anything. Reporting lets us know about abusive content.")
                        .font(.bond(.caption))
                        .foregroundStyle(.secondary)
                }
            } header: {
                BondSectionHeader(title: "Pairing")
            }
            .bondWarmRow()

            Section {
                if purchases.isPremium {
                    if let since = purchases.premiumSince {
                        LabeledContent("Status") {
                            Text("Bond+ since \(since.formatted(date: .long, time: .omitted))")
                                .foregroundStyle(.secondary)
                                .font(.bond(.callout))
                        }
                    } else {
                        LabeledContent("Status", value: "Bond+")
                    }
                    Link("Manage subscription",
                         destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                } else {
                    LabeledContent("Status", value: "Free")
                    // Free users previously had no purchase path here at all —
                    // only a Restore button. Settings is where people go
                    // looking to upgrade; never leave them without a door.
                    Button {
                        isPaywallPresented = true
                    } label: {
                        Label("Try Bond+ free", systemImage: "sparkles")
                            .font(.bond(.body, weight: .semibold))
                            .foregroundStyle(Color.bondAccent)
                    }
                }
                Button {
                    Task {
                        isRestoring = true
                        defer { isRestoring = false }
                        await purchases.restore()
                        // Success updates the Status row above; only the
                        // failure / nothing-found case needs explaining.
                        if !purchases.isPremium { showRestoreResult = true }
                    }
                } label: {
                    if isRestoring { ProgressView() } else { Text("Restore purchases") }
                }
                .disabled(isRestoring)
            } header: {
                BondSectionHeader(title: "Bond+")
            }
            .bondWarmRow()
            .alert("Restore Purchases", isPresented: $showRestoreResult) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(purchases.lastError
                     ?? "No active Bond+ purchase found for this Apple ID.")
            }

            Section {
                Picker("Accent", selection: $theme.accent) {
                    ForEach(BondTheme.Accent.allCases) { accent in
                        HStack {
                            Circle()
                                .fill(accent.color)
                                .frame(width: 14, height: 14)
                            Text(accent.title)
                        }
                        .tag(accent)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                Picker("Appearance", selection: $theme.appearance) {
                    ForEach(BondTheme.Appearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                BondSectionHeader(title: "Theme")
            }
            .bondWarmRow()

            Section {
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
            } header: {
                BondSectionHeader(title: "Notifications")
            }
            .bondWarmRow()

            Section {
                Button {
                    ReviewPromptCoordinator.shared.requestEnjoymentPrompt()
                } label: {
                    Label("Rate or Send Feedback", systemImage: "star.bubble")
                }
            } header: {
                BondSectionHeader(title: "Help")
            }
            .bondWarmRow()

            Section {
                Link("Privacy policy", destination: URL(string: "https://jackwallner.com/bond/privacy")!)
                Link("Terms of service", destination: URL(string: "https://jackwallner.com/bond/terms")!)
                Link("Support", destination: URL(string: "mailto:jackwallner+b@gmail.com")!)
            } footer: {
                HStack {
                    Spacer()
                    Text("Version \(appVersion) (build \(appBuild))")
                        .font(.bond(.footnote))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }
            .bondWarmRow()
        }
        .bondWarmList()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            notificationStatus = await UNUserNotificationCenter.current()
                .notificationSettings().authorizationStatus
        }
        .sheet(isPresented: $isPairingPresented) {
            PairingView()
        }
        .paywallSheet(isPresented: $isPaywallPresented)
        .onChange(of: pairing.justPaired) { _, paired in
            if paired { isPairingPresented = false }
        }
        .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                Task {
                    await purchases.signOut()
                    await supabase.signOut()
                    pairing.reset()
                    // The old account's reminders must stop firing and stop
                    // showing on widgets for whoever signs in next.
                    NotificationScheduler.shared.clearAll()
                    WidgetSnapshotPump.clear()
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
        .confirmationDialog("Delete account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account and everything you created. If you're paired, your partner keeps their own reminders, your shared milestones, and their account — they'll just be unpaired. This can't be undone. (Any App Store subscription is managed separately in Settings → Apple ID.)")
        }
    }

    private func deleteAccount() {
        Task {
            isDeleting = true
            deleteError = nil
            defer { isDeleting = false }
            do {
                try await supabase.deleteAccount()
                await purchases.signOut()
                pairing.reset()
                NotificationScheduler.shared.clearAll()
                WidgetSnapshotPump.clear()
            } catch {
                deleteError = "Couldn't delete your account. Check your connection and try again."
            }
        }
    }

    private var notificationStateLabel: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: "On"
        case .denied: "Off, open Settings"
        default: "Not yet enabled"
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
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
            .font(.bond(.subheadline, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(Color.bondAccent, in: Circle())
            .accessibilityHidden(true)
    }
}
