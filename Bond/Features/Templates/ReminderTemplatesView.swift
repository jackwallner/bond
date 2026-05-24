import SwiftUI

struct ReminderTemplatesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PurchasesService.self) private var store
    @State private var isPaywallPresented = false

    var body: some View {
        NavigationStack {
            Group {
                if !store.isPremium {
                    BondGatePreview(feature: .templates, isPaywallPresented: $isPaywallPresented) {
                        TemplatesGateContent()
                    }
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

    private var list: some View {
        List(ReminderTemplateStore.groups) { group in
            Section {
                NavigationLink {
                    TemplateGroupDetailView(group: group)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: group.icon)
                            .font(.bond(.title2))
                            .foregroundStyle(.pink)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.title)
                                .font(.bond(.headline))
                            Text(group.subtitle)
                                .font(.bond(.caption))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("\(group.reminders.count) reminders")
                    .font(.bond(.caption))
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
    @State private var importError: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.title)
                        .font(.bond(.title2, weight: .bold))
                    Text(group.subtitle)
                        .font(.bond(.subheadline))
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
                                .font(.bond(.subheadline))
                            if let body = template.body {
                                Text(body)
                                    .font(.bond(.caption))
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
                                    .font(.bond(.caption2))
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
                                .font(.bond(.headline))
                        }
                        Spacer()
                    }
                }
                .disabled(isCreating)
                .buttonStyle(.borderedProminent)
                if let importError {
                    Text(importError)
                        .font(.bond(.footnote))
                        .foregroundStyle(.red)
                }
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
        importError = nil

        let partnerId = pairing.partnerProfile?.id
        let targetId: UUID = pairing.solo ? me : (partnerId ?? me)
        let now = Date()

        let drafts: [ReminderDTO] = group.reminders.enumerated().map { index, template in
            // Stagger the initial fire times so importing 7 reminders doesn't
            // dogpile 7 notifications into the same minute. Recurring items
            // anchor at staggered days; one-time items spread across coming
            // afternoons.
            let dayOffset = Double(index)
            let hour: Double = template.triggerRecurrence == nil ? 14 : 9 // 2pm vs 9am
            let fireAt = now
                .addingTimeInterval(dayOffset * 24 * 60 * 60)
                .addingTimeInterval(hour * 60 * 60)

            return ReminderDTO(
                id: UUID(),
                coupleId: coupleId,
                authorId: me,
                targetId: targetId,
                title: template.title,
                body: template.body,
                loveLanguage: template.loveLanguage,
                triggerType: template.triggerRecurrence != nil ? "recurring" : "one_time",
                fireAt: fireAt,
                rrule: template.triggerRecurrence?.rrule,
                geofence: nil,
                windowStart: nil,
                windowEnd: nil,
                status: "scheduled",
                surpriseHiddenFromPartner: false,
                createdAt: nil
            )
        }

        do {
            try await repo.bulkInsert(drafts)
            createdCount = drafts.count
            showConfirmation = true
        } catch {
            // Surface a real error instead of celebrating zero inserts.
            createdCount = 0
            importError = "Couldn't add templates. Check your connection and try again."
        }

        isCreating = false
    }
}
