import CoreLocation
import SwiftUI

struct ReminderEditorView: View {
    @Environment(SupabaseService.self) private var supabase
    @Environment(PairingService.self) private var pairing
    @Environment(ReminderRepository.self) private var repo
    @Environment(ReminderEventRepository.self) private var eventsRepo
    @Environment(PurchasesService.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isUnfoldedSplit) private var isUnfoldedSplit
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
    @State private var randomRepeatsDaily = false
    @State private var dailyWindowStart = Calendar.current.date(
        bySettingHour: 18, minute: 0, second: 0, of: .now) ?? .now
    @State private var dailyWindowEnd = Calendar.current.date(
        bySettingHour: 21, minute: 0, second: 0, of: .now) ?? .now
    @State private var geofenceLatitude: Double = 0
    @State private var geofenceLongitude: Double = 0
    @State private var geofenceLabel: String = GeofenceLabel.display(GeofenceLabel.stableDefault)
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
                        .disabled(isPartnerRequest)
                    TextField("Note (optional)", text: $noteText, axis: .vertical)
                        .lineLimit(2...4)
                        .disabled(isPartnerRequest)
                } footer: {
                    if title.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Add a title to save.")
                    }
                }
                .bondWarmRow()

                Section {
                    loveLanguagePicker
                        .disabled(isPartnerRequest)
                    if isPartnerRequest {
                        EmptyView()
                    } else if pairing.solo {
                        LabeledContent("For", value: String(localized: "You"))
                    } else {
                        Picker("For", selection: $target) {
                            ForEach(ReminderTarget.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        if target == .partner && triggerKind != .location {
                            Toggle("Surprise (hidden from partner)", isOn: $surpriseHidden)
                        }
                    }
                }
                .bondWarmRow()

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
                    BondSectionHeader(title: String(localized: "When"))
                } footer: {
                    if !store.isPremium {
                        Text("Location & surprise-in-a-window need Little Gestures+.")
                            .font(.bond(.caption))
                            .foregroundStyle(.bondTextSecondary)
                    }
                }
                .bondWarmRow()

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.bond(.footnote))
                    }
                    .bondWarmRow()
                }

                if !isPartnerRequest {
                    ideasAndTemplatesSection
                }
            }
            .bondWarmList()
            .navigationTitle(navigationTitle)
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
            .unfoldedSheet(isPresented: $isTemplatesPresented) {
                ReminderTemplatesView()
            }
            .onAppear(perform: hydrate)
        }
        // Unfolded, the form's last rows end whole above the home indicator.
        .clearsFloatingTabBar(isUnfoldedSplit)
        // Unfolded, the form sits on the leading side of the fold and the
        // reminder as it will arrive and as it will list sits on the other.
        .unfoldedLeadingPane {
            ReminderPreviewPane(
                reminder: previewReminder,
                currentUserId: supabase.currentUserId,
                when: previewWhen,
                audience: previewAudience,
                languageNote: previewLanguageNote
            )
        }
    }

    /// A reminder the partner wrote: the words stay theirs, the time is this
    /// user's to change.
    private var isPartnerRequest: Bool {
        guard let existing, let me = supabase.currentUserId else { return false }
        return existing.authorId != me
    }

    private var navigationTitle: String {
        if isPartnerRequest { return String(localized: "Reschedule") }
        return existing == nil ? String(localized: "New reminder") : String(localized: "Edit reminder")
    }

    /// Label on its own line, then one scrollable row of chips clearly below
    /// it - the menu-style picker squeezed the icon+title onto the trailing
    /// edge where long titles wrapped awkwardly. In the unfolded Duo's pane
    /// all five wrap into view instead, so none is cut at the card edge. At
    /// accessibility sizes one chip can be wider than the card, so they stack.
    private var loveLanguagePicker: some View {
        VStack(alignment: .leading, spacing: BondSpacing.s) {
            Text("Love language")
                .font(.bond(.body))
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: BondSpacing.s) { loveLanguageChips }
            } else if isUnfoldedSplit {
                FlowLayout { loveLanguageChips }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: BondSpacing.s) { loveLanguageChips }
                }
            }
        }
        .padding(.vertical, BondSpacing.xs)
    }

    private var loveLanguageChips: some View {
        ForEach(LoveLanguage.allCases) { lang in
            let selected = lang == loveLanguage
            Button {
                loveLanguage = lang
            } label: {
                HStack(spacing: BondSpacing.xs) {
                    Image(systemName: lang.symbolName)
                        .font(.bond(.footnote))
                    Text(lang.title)
                        .font(.bond(.footnote, weight: selected ? .semibold : .regular))
                }
                .padding(.horizontal, BondSpacing.m)
                .padding(.vertical, BondSpacing.s)
                .foregroundStyle(selected ? .white : lang.textTint)
                .background(
                    selected ? AnyShapeStyle(lang.chipFill) : AnyShapeStyle(lang.tint.opacity(0.12)),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }

    // MARK: - Unfolded preview

    private var previewTargetId: UUID? {
        target == .partner && !pairing.solo
            ? pairing.partnerProfile?.id ?? supabase.currentUserId
            : supabase.currentUserId
    }

    /// The form as a reminder, for the preview pane only; `save()` builds
    /// the stored one.
    private var previewReminder: ReminderDTO {
        let me = supabase.currentUserId ?? UUID()
        var draft = ReminderDTO(
            id: existing?.id ?? me,
            coupleId: existing?.coupleId ?? me,
            authorId: existing?.authorId ?? me,
            targetId: previewTargetId ?? me,
            title: title.trimmingCharacters(in: .whitespaces).isEmpty ? String(localized: "Your reminder") : title,
            body: noteText.isEmpty ? nil : noteText,
            loveLanguage: loveLanguage,
            triggerType: "one_time",
            fireAt: fireAt,
            rrule: nil,
            geofence: nil,
            windowStart: nil,
            windowEnd: nil,
            status: "scheduled",
            surpriseHiddenFromPartner: target == .partner && triggerKind != .location && surpriseHidden,
            createdAt: nil
        )
        switch triggerKind {
        case .oneTime:
            break
        case .recurring:
            draft.triggerType = "recurring"
            draft.rrule = recurrence.rrule
        case .location:
            draft.triggerType = "location"
            draft.fireAt = nil
            if geofenceConfigured {
                draft.geofence = Geofence(
                    latitude: geofenceLatitude,
                    longitude: geofenceLongitude,
                    radiusMeters: 200,
                    label: GeofenceLabel.stored(geofenceLabel)
                )
            }
        case .randomWindow:
            draft.triggerType = "random_window"
            draft.fireAt = nil
            draft.windowStart = randomRepeatsDaily ? dailyWindowStart : windowStart
            draft.windowEnd = randomRepeatsDaily ? dailyWindowEnd : windowEnd
            draft.rrule = randomRepeatsDaily ? RecurrencePreset.daily.rrule : nil
        }
        return draft
    }

    /// When the nudge lands, in the notification's corner.
    private var previewWhen: String {
        switch triggerKind {
        case .oneTime, .recurring:
            fireAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        case .location:
            String(localized: "At \(geofenceLabel)")
        case .randomWindow:
            String(localized: "Surprise")
        }
    }

    /// How the chosen language sits among the couple's other reminders.
    private var previewLanguageNote: String {
        let others = repo.reminders.filter { $0.loveLanguage == loveLanguage && $0.id != existing?.id }.count
        switch others {
        case 0: return loveLanguage.firstReminderNote
        default: return loveLanguage.otherRemindersNote(others)
        }
    }

    /// Who sees it, under the list row. Solo has no one to tell.
    private var previewAudience: String? {
        guard !pairing.solo else { return nil }
        let partner = pairing.partnerProfile?.displayName.flatMap { $0.isEmpty ? nil : $0 }
        switch target {
        case .me:
            return String(localized: "Only you see this one.")
        case .partner:
            if surpriseHidden && triggerKind != .location {
                return partner.map { String(localized: "A surprise: \($0) won't see it in their list.") }
                    ?? String(localized: "A surprise: Your partner won't see it in their list.")
            }
            return partner.map { String(localized: "\($0) sees it in their list too.") }
                ?? String(localized: "Your partner sees it in their list too.")
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
                                        .foregroundStyle(chip.loveLanguage.textTint)
                                    Text(chip.displayTitle)
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
                            .accessibilityLabel("Use suggestion: \(chip.displayTitle)")
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
            .bondWarmRow()
        } header: {
            BondSectionHeader(title: existing == nil ? String(localized: "Need an idea?") : String(localized: "Templates"))
        }
    }

    private var isFormValid: Bool {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch triggerKind {
        case .location:     return geofenceConfigured
        case .randomWindow:
            return randomRepeatsDaily
                ? minutesOfDay(dailyWindowEnd) > minutesOfDay(dailyWindowStart)
                : windowEnd > windowStart
        case .oneTime, .recurring: return true
        }
    }

    private func minutesOfDay(_ date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
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
                    geofenceConfigured ? String(localized: "Update to current location") : String(localized: "Use current location"),
                    systemImage: "location.fill"
                )
            }
            if geofenceConfigured {
                Text(String(localized: "\(geofenceLatitude.formatted(.number.precision(.fractionLength(4)))), \(geofenceLongitude.formatted(.number.precision(.fractionLength(4)))) (200m radius)"))
                    .font(.bond(.caption2))
                    .foregroundStyle(.bondTextSecondary)
            } else {
                Text("Tap above to capture a location before saving.")
                    .font(.bond(.caption2))
                    .foregroundStyle(.orange)
            }
        case .randomWindow:
            Toggle("Repeat every day", isOn: $randomRepeatsDaily)
            if randomRepeatsDaily {
                DatePicker(
                    "Between", selection: $dailyWindowStart,
                    displayedComponents: .hourAndMinute
                )
                DatePicker(
                    "and", selection: $dailyWindowEnd,
                    displayedComponents: .hourAndMinute
                )
                if minutesOfDay(dailyWindowEnd) <= minutesOfDay(dailyWindowStart) {
                    Text("The end time must be after the start time.")
                        .font(.bond(.footnote))
                        .foregroundStyle(.orange)
                } else {
                    Text("Fires once a day, at a different random time in this window each day.")
                        .font(.bond(.footnote))
                        .foregroundStyle(.bondTextSecondary)
                }
            } else {
                DatePicker("Earliest", selection: $windowStart)
                DatePicker("Latest", selection: $windowEnd)
                if windowEnd <= windowStart {
                    Text("Latest must be after Earliest.")
                        .font(.bond(.footnote))
                        .foregroundStyle(.orange)
                } else {
                    Text("Little Gestures will pick one random moment in this window.")
                        .font(.bond(.footnote))
                        .foregroundStyle(.bondTextSecondary)
                }
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
            geofenceLabel = GeofenceLabel.display(g.label)
            geofenceLatitude = g.latitude
            geofenceLongitude = g.longitude
            geofenceConfigured = true
        case .randomWindow(let s, let e):
            triggerKind = .randomWindow
            randomRepeatsDaily = false
            windowStart = s
            windowEnd = e
        case .randomRecurring(let s, let e):
            triggerKind = .randomWindow
            randomRepeatsDaily = true
            dailyWindowStart = s
            dailyWindowEnd = e
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
            errorMessage = String(localized: "Not set up yet. Please finish setup first.")
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
        // Only the server can deliver a surprise, and it cannot tell where the
        // partner is, so a place is never one.
        draft.surpriseHiddenFromPartner = target == .partner && triggerKind != .location && surpriseHidden

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
                errorMessage = String(localized: "Pick a location first.")
                return
            }
            draft.triggerType = "location"
            draft.geofence = Geofence(
                latitude: geofenceLatitude,
                longitude: geofenceLongitude,
                radiusMeters: 200,
                label: GeofenceLabel.stored(geofenceLabel)
            )
            draft.fireAt = nil
            draft.rrule = nil
            draft.windowStart = nil
            draft.windowEnd = nil
        case .randomWindow:
            if randomRepeatsDaily {
                guard minutesOfDay(dailyWindowEnd) > minutesOfDay(dailyWindowStart) else {
                    errorMessage = String(localized: "The end time must be after the start time.")
                    return
                }
                draft.triggerType = "random_window"
                draft.rrule = RecurrencePreset.daily.rrule
                draft.windowStart = dailyWindowStart
                draft.windowEnd = dailyWindowEnd
                // fireAt is only used for ordering/widgets; the scheduler
                // re-derives each day's random moment itself.
                let trigger = ReminderTrigger.randomRecurring(
                    start: dailyWindowStart, end: dailyWindowEnd
                )
                draft.fireAt = trigger.upcomingFireDate()
                draft.geofence = nil
            } else {
                guard windowEnd > windowStart else {
                    errorMessage = String(localized: "Window end must be after start.")
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
        }

        do {
            try await repo.upsert(draft)
            await repo.rescheduleNotifications(forSelfUserId: me, events: eventsRepo.loadedEvents)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}


/// The unfolded editor's trailing pane: the reminder as the notification
/// that will arrive, the row it will be in the list and its love language,
/// updating as the form changes. No navigation bar: one here, with its
/// vertical bars disabled to level the titles, inset the whole cover 42 pt
/// from both display edges. The title is placed by hand instead, its
/// baseline level with the form's large title (117.7 pt down on the Duo).
private struct ReminderPreviewPane: View {
    let reminder: ReminderDTO
    let currentUserId: UUID?
    let when: String
    let audience: String?
    let languageNote: String

    /// Top of the 34 pt title, so its baseline (ascender 1.038 em) sits at
    /// the large title's.
    private static let titleTop: CGFloat = 82

    var body: some View {
        // A scroll view, so the pane's minimum height is zero. As a plain stack
        // it was taller than the space left above the keyboard, which made the
        // whole cover taller than the display and slid the form's navigation
        // bar (Cancel, Save) off the top while the keyboard was up.
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Preview")
                    .font(.bond(.largeTitle, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, Self.titleTop)
                section(String(localized: "How it arrives")) { notification }
                section(String(localized: "In your list"), footer: audience) {
                    ReminderRow(reminder: reminder, currentUserId: currentUserId)
                }
                section(String(localized: "Love language")) { language }
            }
            .padding(.horizontal, BondSpacing.l)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The status bar sits in the pane's top trailing corner, beside the
        // title and above the first card.
        .ignoresSafeArea(edges: [.top, .trailing])
        .environment(\.horizontalSizeClass, .compact)
    }

    private func section<Content: View>(
        _ title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: BondSpacing.s) {
            BondSectionHeader(title: title)
                .padding(.horizontal, BondSpacing.l)
            content()
                .padding(.horizontal, BondSpacing.l)
                .padding(.vertical, BondSpacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bondCardFill, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            if let footer {
                Text(footer)
                    .font(.bond(.footnote))
                    .foregroundStyle(.bondTextSecondary)
                    .padding(.horizontal, BondSpacing.l)
            }
        }
        .padding(.top, BondSpacing.xl)
    }

    private var language: some View {
        HStack(spacing: BondSpacing.m) {
            Image(systemName: reminder.loveLanguage.symbolName)
                .font(.bond(.body))
                .foregroundStyle(reminder.loveLanguage.tint)
                .frame(width: 38, height: 38)
                .background(reminder.loveLanguage.tint.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.loveLanguage.title)
                    .font(.bond(.headline))
                Text(languageNote)
                    .font(.bond(.subheadline))
                    .foregroundStyle(.bondTextSecondary)
            }
        }
        .padding(.vertical, BondSpacing.xs)
    }

    private var notification: some View {
        HStack(alignment: .top, spacing: BondSpacing.m) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color.bondAccent.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(BondBrand.name)
                        .font(.bond(.caption, weight: .semibold))
                        .foregroundStyle(.bondTextSecondary)
                    Spacer()
                    Text(when)
                        .font(.bond(.caption))
                        .foregroundStyle(.bondTextSecondary)
                }
                Text(reminder.title)
                    .font(.bond(.subheadline, weight: .semibold))
                    .lineLimit(2)
                if let body = reminder.body, !body.isEmpty {
                    Text(body)
                        .font(.bond(.subheadline))
                        .lineLimit(3)
                }
            }
        }
        .padding(.vertical, BondSpacing.xs)
    }
}
