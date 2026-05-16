import SwiftUI

struct ReminderTemplatesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PurchasesService.self) private var store
    @State private var isPaywallPresented = false

    var body: some View {
        NavigationStack {
            Group {
                if !store.isPremium {
                    gate
                } else {
                    list
                }
            }
            .navigationTitle("Templates")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .paywallSheet(isPresented: $isPaywallPresented)
        }
    }

    private var gate: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 56))
                .foregroundStyle(.pink)
            Text("Templates is a premium feature")
                .font(.headline)
            Text("Get pre-built reminder packs for every relationship stage — daily affirmations, date nights, long-distance love, and more.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Unlock Premium") { isPaywallPresented = true }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var list: some View {
        List(ReminderTemplateStore.groups) { group in
            Section {
                NavigationLink {
                    TemplateGroupDetailView(group: group)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: group.icon)
                            .font(.title2)
                            .foregroundStyle(.pink)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.title)
                                .font(.headline)
                            Text(group.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("\(group.reminders.count) reminders")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct TemplateGroupDetailView: View {
    let group: ReminderTemplateGroup
    @Environment(\.dismiss) private var dismiss
    @Environment(ReminderRepository.self) private var repo
    @Environment(PairingService.self) private var pairing
    @Environment(SupabaseService.self) private var supabase
    @State private var isCreating = false
    @State private var createdCount = 0
    @State private var showConfirmation = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.title)
                        .font(.title2.bold())
                    Text(group.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("Includes") {
                ForEach(group.reminders) { template in
                    HStack(spacing: 12) {
                        Image(systemName: template.loveLanguage.symbolName)
                            .foregroundStyle(template.loveLanguage.tint)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.title)
                                .font(.subheadline)
                            if let body = template.body {
                                Text(body)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(template.loveLanguage.tint)
                                .frame(width: 8, height: 8)
                            if let preset = template.triggerRecurrence {
                                Text(preset.title)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    Task { await createAll() }
                } label: {
                    HStack {
                        Spacer()
                        if isCreating {
                            ProgressView()
                        } else {
                            Text("Add \(group.reminders.count) reminders")
                                .font(.headline)
                        }
                        Spacer()
                    }
                }
                .disabled(isCreating)
                .buttonStyle(.borderedProminent)
            }
        }
        .alert("Templates added!", isPresented: $showConfirmation) {
            Button("Done") { dismiss() }
        } message: {
            Text("\(createdCount) reminders have been added to your list. Customize them anytime.")
        }
    }

    private func createAll() async {
        guard let me = supabase.currentUserId,
              let coupleId = pairing.coupleId
        else { return }

        isCreating = true
        createdCount = 0

        for template in group.reminders {
            let partnerId = pairing.partnerProfile?.id
            let targetId: UUID
            if pairing.solo {
                targetId = me
            } else {
                // Target partner for love language reminders, self for personal ones
                targetId = partnerId ?? me
            }

            let reminder = ReminderDTO(
                id: UUID(),
                coupleId: coupleId,
                authorId: me,
                targetId: targetId,
                title: template.title,
                body: template.body,
                loveLanguage: template.loveLanguage,
                triggerType: template.triggerRecurrence != nil ? "recurring" : "one_time",
                fireAt: Date().addingTimeInterval(60 * 60),
                rrule: template.triggerRecurrence?.rrule,
                geofence: nil,
                windowStart: nil,
                windowEnd: nil,
                status: "scheduled",
                surpriseHiddenFromPartner: false,
                createdAt: nil
            )

            do {
                try await repo.upsert(reminder)
                createdCount += 1
            } catch {
                break
            }
        }

        isCreating = false
        showConfirmation = true
    }
}
