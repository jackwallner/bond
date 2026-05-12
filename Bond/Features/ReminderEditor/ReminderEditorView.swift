import SwiftUI

enum ReminderTarget: String, CaseIterable, Identifiable {
    case me
    case partner

    var id: String { rawValue }
    var title: String { self == .me ? "Me" : "Partner" }
}

enum TriggerKind: String, CaseIterable, Identifiable {
    case oneTime
    case recurring

    var id: String { rawValue }
    var title: String { self == .oneTime ? "One time" : "Recurring" }
}

struct ReminderEditorView: View {
    @Environment(SupabaseService.self) private var supabase
    @Environment(PairingService.self) private var pairing
    @Environment(ReminderRepository.self) private var repo
    @Environment(\.dismiss) private var dismiss

    var existing: ReminderDTO?

    @State private var title = ""
    @State private var noteText = ""
    @State private var loveLanguage: LoveLanguage = .words
    @State private var target: ReminderTarget = .me
    @State private var triggerKind: TriggerKind = .oneTime
    @State private var fireAt: Date = Date().addingTimeInterval(60 * 60)
    @State private var recurrence: RecurrencePreset = .weekly
    @State private var surpriseHidden = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Note (optional)", text: $noteText, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("Love language") {
                    Picker("Love language", selection: $loveLanguage) {
                        ForEach(LoveLanguage.allCases) { lang in
                            Label(lang.title, systemImage: lang.symbolName)
                                .tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Who is this for?") {
                    Picker("Target", selection: $target) {
                        ForEach(ReminderTarget.allCases) { t in
                            Text(t.title).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    if target == .partner {
                        Toggle("Keep secret from partner (surprise)", isOn: $surpriseHidden)
                    }
                }

                Section("When") {
                    Picker("Trigger", selection: $triggerKind) {
                        ForEach(TriggerKind.allCases) { t in
                            Text(t.title).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)

                    DatePicker(
                        triggerKind == .oneTime ? "Date & time" : "Starting",
                        selection: $fireAt
                    )

                    if triggerKind == .recurring {
                        Picker("Repeat", selection: $recurrence) {
                            ForEach(RecurrencePreset.allCases) { p in
                                Text(p.title).tag(p)
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(existing == nil ? "New reminder" : "Edit reminder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: { Task { await save() } }) {
                        if isSaving { ProgressView() } else { Text("Save") }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear(perform: hydrate)
        }
    }

    private func hydrate() {
        guard let existing else { return }
        title = existing.title
        noteText = existing.body ?? ""
        loveLanguage = existing.loveLanguage
        target = (existing.targetId == supabase.currentUserId) ? .me : .partner
        surpriseHidden = existing.surpriseHiddenFromPartner

        switch existing.trigger {
        case .oneTime(let d):
            triggerKind = .oneTime
            fireAt = d
        case .recurring(let r, let d):
            triggerKind = .recurring
            fireAt = d
            if let p = RecurrencePreset(rrule: r) { recurrence = p }
        default: break
        }
    }

    private func save() async {
        guard let me = supabase.currentUserId,
              let coupleId = pairing.coupleId
        else {
            errorMessage = "Not paired yet."
            return
        }
        let partnerId = pairing.partnerProfile?.id
        let targetId: UUID = switch target {
        case .me:      me
        case .partner: partnerId ?? me
        }

        isSaving = true
        defer { isSaving = false }

        var draft = existing ?? ReminderDTO(
            id: UUID(),
            coupleId: coupleId,
            authorId: me,
            targetId: targetId,
            title: title,
            body: noteText.isEmpty ? nil : noteText,
            loveLanguage: loveLanguage,
            triggerType: "one_time",
            fireAt: fireAt,
            rrule: nil,
            geofence: nil,
            windowStart: nil,
            windowEnd: nil,
            status: "scheduled",
            surpriseHiddenFromPartner: surpriseHidden,
            createdAt: nil
        )
        draft.title = title
        draft.body = noteText.isEmpty ? nil : noteText
        draft.loveLanguage = loveLanguage
        draft.targetId = targetId
        draft.surpriseHiddenFromPartner = (target == .partner) ? surpriseHidden : false

        switch triggerKind {
        case .oneTime:
            draft.triggerType = "one_time"
            draft.fireAt = fireAt
            draft.rrule = nil
        case .recurring:
            draft.triggerType = "recurring"
            draft.fireAt = fireAt
            draft.rrule = recurrence.rrule
        }

        do {
            try await repo.upsert(draft)
            await NotificationScheduler.shared.reschedule(
                forSelfUserId: me, reminders: repo.reminders
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
