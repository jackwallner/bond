import CoreLocation
import SwiftUI

struct ReminderEditorView: View {
    @Environment(SupabaseService.self) private var supabase
    @Environment(PairingService.self) private var pairing
    @Environment(ReminderRepository.self) private var repo
    @Environment(PurchasesService.self) private var store
    @Environment(\.dismiss) private var dismiss

    var existing: ReminderDTO?
    /// Optional seed for a brand-new reminder (e.g. tapped from a starter
    /// chip). Ignored when `existing` is set.
    var prefill: (title: String, language: LoveLanguage)?

    @State private var title = ""
    @State private var noteText = ""
    @State private var loveLanguage: LoveLanguage = .words
    @State private var target: ReminderTarget = .me
    @State private var triggerKind: TriggerKind = .oneTime
    @State private var fireAt: Date = Date().addingTimeInterval(60 * 60)
    @State private var recurrence: RecurrencePreset = .weekly
    @State private var surpriseHidden = false
    @State private var windowStart = Date().addingTimeInterval(60 * 60)
    @State private var windowEnd = Date().addingTimeInterval(60 * 60 * 24)
    @State private var geofenceLatitude: Double = 0
    @State private var geofenceLongitude: Double = 0
    @State private var geofenceLabel: String = "Home"
    @State private var geofenceConfigured = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isPaywallPresented = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Note (optional)", text: $noteText, axis: .vertical)
                        .lineLimit(2...5)
                } footer: {
                    if title.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Add a title to save.")
                    }
                }

                Section("Love language") {
                    Picker("Love language", selection: $loveLanguage) {
                        ForEach(LoveLanguage.allCases) { lang in
                            Label(lang.title, systemImage: lang.symbolName)
                                .foregroundStyle(lang.tint)
                                .tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Section("Who is this for?") {
                    if pairing.solo {
                        // Solo users only target themselves.
                        Text("Reminders are just for you.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Target", selection: $target) {
                            ForEach(ReminderTarget.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        if target == .partner {
                            Toggle("Keep secret from partner (surprise)", isOn: $surpriseHidden)
                        }
                    }
                }

                Section("When") {
                    Picker("Trigger", selection: $triggerKind) {
                        ForEach(TriggerKind.allCases) { kind in
                            HStack {
                                Text(kind.title)
                                if kind.isPremium && !store.isPremium {
                                    Spacer()
                                    Image(systemName: "lock.fill")
                                        .foregroundStyle(.secondary)
                                        .font(.caption2)
                                }
                            }
                            .tag(kind)
                        }
                    }
                    .onChange(of: triggerKind) { _, newValue in
                        if newValue.isPremium && !store.isPremium {
                            isPaywallPresented = true
                            triggerKind = .oneTime
                        }
                    }

                    triggerDetail
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
            .paywallSheet(isPresented: $isPaywallPresented)
            .onAppear(perform: hydrate)
        }
    }

    @ViewBuilder
    private var triggerDetail: some View {
        switch triggerKind {
        case .oneTime:
            DatePicker("Date & time", selection: $fireAt)
        case .recurring:
            DatePicker("Starting", selection: $fireAt)
            Picker("Repeat", selection: $recurrence) {
                ForEach(RecurrencePreset.allCases) { Text($0.title).tag($0) }
            }
        case .location:
            HStack {
                TextField("Place name", text: $geofenceLabel)
                Spacer()
                if geofenceConfigured {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
            Button {
                Task { await captureCurrentLocation() }
            } label: {
                Label(
                    geofenceConfigured ? "Update to current location" : "Use current location",
                    systemImage: "location.fill"
                )
            }
            if geofenceConfigured {
                Text(String(format: "%.4f, %.4f (200m radius)", geofenceLatitude, geofenceLongitude))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .randomWindow:
            DatePicker("Earliest", selection: $windowStart)
            DatePicker("Latest", selection: $windowEnd)
            Text("Bond will pick a random moment in this window.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func captureCurrentLocation() async {
        do {
            let loc = try await LocationService.shared.currentLocation()
            geofenceLatitude = loc.coordinate.latitude
            geofenceLongitude = loc.coordinate.longitude
            geofenceConfigured = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func hydrate() {
        guard let existing else {
            if let prefill {
                title = prefill.title
                loveLanguage = prefill.language
            }
            return
        }
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
        case .location(let g, _):
            triggerKind = .location
            geofenceLabel = g.label
            geofenceLatitude = g.latitude
            geofenceLongitude = g.longitude
            geofenceConfigured = true
        case .randomWindow(let s, let e):
            triggerKind = .randomWindow
            windowStart = s
            windowEnd = e
        default: break
        }
    }

    private func save() async {
        guard let me = supabase.currentUserId,
              let coupleId = pairing.coupleId
        else {
            errorMessage = "Not set up yet. Please finish setup first."
            return
        }
        let partnerId = pairing.partnerProfile?.id
        let targetId: UUID = switch target {
        case .me:      me
        case .partner: partnerId ?? me
        }

        if triggerKind.isPremium && !store.isPremium {
            isPaywallPresented = true
            return
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
            draft.geofence = nil
            draft.windowStart = nil
            draft.windowEnd = nil
        case .recurring:
            draft.triggerType = "recurring"
            draft.fireAt = fireAt
            draft.rrule = recurrence.rrule
            draft.geofence = nil
            draft.windowStart = nil
            draft.windowEnd = nil
        case .location:
            guard geofenceConfigured else {
                errorMessage = "Pick a location first."
                return
            }
            draft.triggerType = "location"
            draft.geofence = Geofence(
                latitude: geofenceLatitude,
                longitude: geofenceLongitude,
                radiusMeters: 200,
                label: geofenceLabel
            )
            draft.fireAt = nil
            draft.rrule = nil
            draft.windowStart = nil
            draft.windowEnd = nil
        case .randomWindow:
            guard windowEnd > windowStart else {
                errorMessage = "Window end must be after start."
                return
            }
            let interval = windowEnd.timeIntervalSince(windowStart)
            let pick = windowStart.addingTimeInterval(.random(in: 0...interval))
            draft.triggerType = "random_window"
            draft.fireAt = pick
            draft.windowStart = windowStart
            draft.windowEnd = windowEnd
            draft.rrule = nil
            draft.geofence = nil
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
