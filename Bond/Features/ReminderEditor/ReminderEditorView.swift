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
    @State private var isTemplatesPresented = false
    @State private var lastFreeTriggerKind: TriggerKind = .oneTime

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Note (optional)", text: $noteText, axis: .vertical)
                        .lineLimit(2...4)
                } footer: {
                    if title.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Add a title to save.")
                    }
                }

                Section {
                    Picker("Love language", selection: $loveLanguage) {
                        ForEach(LoveLanguage.allCases) { lang in
                            Label(lang.title, systemImage: lang.symbolName).tag(lang)
                        }
                    }
                    if pairing.solo {
                        LabeledContent("For", value: "You")
                    } else {
                        Picker("For", selection: $target) {
                            ForEach(ReminderTarget.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        if target == .partner {
                            Toggle("Surprise (hidden from partner)", isOn: $surpriseHidden)
                        }
                    }
                }

                Section {
                    Picker("Schedule", selection: $triggerKind) {
                        ForEach(TriggerKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .onChange(of: triggerKind) { _, newKind in
                        if newKind.isPremium && !store.isPremium {
                            triggerKind = lastFreeTriggerKind
                            isPaywallPresented = true
                        } else if !newKind.isPremium {
                            lastFreeTriggerKind = newKind
                        }
                    }
                    triggerDetail
                } header: {
                    Text("When")
                } footer: {
                    if !store.isPremium {
                        Text("Location & surprise-in-a-window need Bond+.")
                            .font(.bond(.caption))
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.bond(.footnote))
                    }
                }

                ideasAndTemplatesSection
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
                    .disabled(!isFormValid || isSaving)
                }
            }
            .paywallSheet(isPresented: $isPaywallPresented)
            .sheet(isPresented: $isTemplatesPresented) {
                ReminderTemplatesView()
            }
            .onAppear(perform: hydrate)
        }
    }

    @ViewBuilder
    private var ideasAndTemplatesSection: some View {
        Section {
            if existing == nil && title.trimmingCharacters(in: .whitespaces).isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: BondSpacing.s) {
                        ForEach(starterChips(for: .shared)) { chip in
                            Button {
                                title = chip.title
                                loveLanguage = chip.loveLanguage
                            } label: {
                                HStack(spacing: BondSpacing.xs) {
                                    Image(systemName: chip.loveLanguage.symbolName)
                                        .font(.bond(.caption))
                                        .foregroundStyle(chip.loveLanguage.tint)
                                    Text(chip.title)
                                        .font(.bond(.caption))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                }
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, BondSpacing.m)
                                .padding(.vertical, BondSpacing.s)
                                .background(Color.bondCardFill, in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.bondHairline, lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Use suggestion: \(chip.title)")
                        }
                    }
                    .padding(.horizontal, BondSpacing.base)
                    .padding(.vertical, BondSpacing.s)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Button {
                isTemplatesPresented = true
            } label: {
                Label("Browse reminder templates", systemImage: "square.grid.2x2")
            }

            if !store.isPremium {
                Text("83% of Bond+ users report a healthier, happier relationship.")
                    .font(.bond(.footnote))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(existing == nil ? "Need an idea?" : "Templates")
        }
    }

    private var isFormValid: Bool {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch triggerKind {
        case .location:     return geofenceConfigured
        case .randomWindow: return windowEnd > windowStart
        case .oneTime, .recurring: return true
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
                    .font(.bond(.caption2))
                    .foregroundStyle(.secondary)
            } else {
                Text("Tap above to capture a location before saving.")
                    .font(.bond(.caption2))
                    .foregroundStyle(.orange)
            }
        case .randomWindow:
            DatePicker("Earliest", selection: $windowStart)
            DatePicker("Latest", selection: $windowEnd)
            if windowEnd <= windowStart {
                Text("Latest must be after Earliest.")
                    .font(.bond(.caption2))
                    .foregroundStyle(.orange)
            } else {
                Text("Bond will pick a random moment in this window.")
                    .font(.bond(.caption2))
                    .foregroundStyle(.secondary)
            }
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
            lastFreeTriggerKind = .oneTime
            fireAt = d
        case .recurring(let r, let d):
            triggerKind = .recurring
            lastFreeTriggerKind = .recurring
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
        if !triggerKind.isPremium {
            lastFreeTriggerKind = triggerKind
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

