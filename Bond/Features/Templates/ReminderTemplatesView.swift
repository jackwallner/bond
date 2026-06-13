import SwiftUI

struct ReminderTemplatesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PurchasesService.self) private var store
    @State private var isPaywallPresented = false

    var body: some View {
        NavigationStack {
            Group {
                if !store.isPremium {
                    teaser
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

    private var teaser: some View {
        Form {
            Section {
                ForEach(ReminderTemplateStore.groups) { group in
                    HStack(spacing: 12) {
                        Image(systemName: group.icon)
                            .font(.bond(.title2))
                            .foregroundStyle(Color.bondAccent)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.title)
                                .font(.bond(.headline))
                            Text(group.subtitle)
                                .font(.bond(.caption))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(group.reminders.count)")
                            .font(.bond(.caption, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .bondWarmRow()

            Section {
                BondUnlockCard(
                    icon: "square.stack.fill",
                    headline: PremiumFeature.templates.gateHeadline,
                    subhead: PremiumFeature.templates.gateSubhead,
                    isPaywallPresented: $isPaywallPresented
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .bondWarmList()
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
                            .foregroundStyle(Color.bondAccent)
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
                BondSectionHeader(title: "\(group.reminders.count) reminders")
            }
            .bondWarmRow()
        }
        .bondWarmList()
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
            .bondWarmRow()

            Section {
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
            } header: {
                BondSectionHeader(title: "Includes")
            }
            .bondWarmRow()

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
            .bondWarmRow()
        }
        .bondWarmList()
        .alert("Templates added!", isPresented: $showConfirmation) {
            Button("Done") { dismiss() }
        } message: {
            Text("\(createdCount) reminders added, spread across the coming days so they arrive one at a time, not all at once. Customize any of them anytime.")
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
        let cal = Calendar.current
        let now = Date()

        let drafts: [ReminderDTO] = group.reminders.enumerated().map { index, template in
            // Anchor each reminder to a friendly clock time - recurring packs at
            // 9am, one-time nudges at 2pm - then stagger one day apart so
            // importing a whole pack doesn't dogpile notifications into one
            // moment. Start from the next occurrence of that hour so one-time
            // items are always in the future (a past fireAt would be dropped
            // by the scheduler).
            let targetHour = template.triggerRecurrence == nil ? 14 : 9 // 2pm vs 9am
            var base = cal.date(bySettingHour: targetHour, minute: 0, second: 0, of: now) ?? now
            if base <= now {
                base = cal.date(byAdding: .day, value: 1, to: base) ?? base
            }
            let fireAt = cal.date(byAdding: .day, value: index, to: base) ?? base

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
