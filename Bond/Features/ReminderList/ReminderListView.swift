import SwiftUI
import UserNotifications

struct ReminderListView: View {
    @Environment(SupabaseService.self) private var supabase
    @Environment(ReminderRepository.self) private var repo
    @Environment(ReminderEventRepository.self) private var eventsRepo
    @Environment(PairingService.self) private var pairing
    @Environment(PurchasesService.self) private var store
    @Environment(DailyCheckInService.self) private var checkIn
    @State private var router = NotificationRouter.shared

    @State private var isEditorPresented = false
    @State private var isTemplatesPresented = false
    @State private var editingReminder: ReminderDTO?
    @State private var showNotificationPrimer = false
    @State private var primerRequestedAuth = false
    @State private var starterPrefill: StarterChip?
    @State private var hasLoadedOnce = false
    @State private var isPairingPresented = false
    /// Reminders with a completion toggle in flight, so a double-tap can't
    /// create duplicate completion events.
    @State private var togglingIds: Set<UUID> = []
    @AppStorage("pairingNudgeDismissed") private var pairingNudgeDismissed = false

    private let primerShownKey = "hasShownNotificationPrimer"

    var body: some View {
        NavigationStack {
            Group {
                if !hasLoadedOnce && repo.isLoading && repo.reminders.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if visibleReminders.isEmpty {
                    EmptyRemindersView(
                        onTapChip: { chip in
                            editingReminder = nil
                            starterPrefill = chip
                            isEditorPresented = true
                        },
                        onBrowseTemplates: { isTemplatesPresented = true }
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Bond")
            .safeAreaInset(edge: .bottom, alignment: .trailing) {
                composeButton
            }
            .sheet(isPresented: $isEditorPresented, onDismiss: { starterPrefill = nil }) {
                ReminderEditorView(
                    existing: editingReminder,
                    prefill: starterPrefill.map { ($0.title, $0.loveLanguage) }
                )
            }
            .sheet(isPresented: $isTemplatesPresented) {
                ReminderTemplatesView()
            }
            .sheet(isPresented: $isPairingPresented) {
                PairingView()
            }
            .sheet(isPresented: $showNotificationPrimer, onDismiss: {
                // "Maybe later" path. The request path posts from its Task
                // instead, after the system dialog has been answered.
                if !primerRequestedAuth {
                    NotificationCenter.default.post(name: .bondNotificationPrimerResolved, object: nil)
                }
            }) {
                NotificationPrimerSheet {
                    primerRequestedAuth = true
                    Task {
                        await NotificationScheduler.shared.requestAuthorizationIfNeeded()
                        // Now that permission is (hopefully) granted, schedule
                        // anything that already exists.
                        await NotificationScheduler.shared.reschedule(
                            forSelfUserId: supabase.currentUserId ?? UUID(),
                            reminders: repo.reminders,
                            events: eventsRepo.events,
                            requestAuthIfNeeded: false
                        )
                        NotificationCenter.default.post(name: .bondNotificationPrimerResolved, object: nil)
                    }
                }
            }
            .refreshable {
                await repo.refresh()
                await eventsRepo.refresh()
            }
            .task {
                await repo.refresh()
                await eventsRepo.refresh()
                hasLoadedOnce = true
                openReminderFromNotification(router.pendingReminderId)
                await repo.subscribeRealtime()
                // Don't let rescheduling fire the bare system prompt here — the
                // primer below explains *why* first, then requests. Without this
                // the primer's `.notDetermined` guard never passes.
                await NotificationScheduler.shared.reschedule(
                    forSelfUserId: supabase.currentUserId ?? UUID(),
                    reminders: repo.reminders,
                    events: eventsRepo.events,
                    requestAuthIfNeeded: false
                )
                await maybeShowNotificationPrimer()
            }
            .onChange(of: router.pendingReminderId) { _, id in
                openReminderFromNotification(id)
            }
            .onAppear { openReminderFromNotification(router.pendingReminderId) }
            .onChange(of: pairing.justPaired) { _, paired in
                // Drop the pairing sheet so RootView's success interstitial
                // isn't hidden underneath it.
                if paired { isPairingPresented = false }
            }
            .onChange(of: pairing.coupleId) { _, _ in
                // Re-subscribe after pair/unpair so realtime points at the
                // new couple. Without this, a freshly-paired user keeps
                // listening on the solo couple's channel and never sees
                // partner-authored reminders until app restart.
                Task {
                    await repo.subscribeRealtime()
                    await repo.refresh()
                    await eventsRepo.refresh()
                }
            }
        }
    }

    /// Open the editor for a reminder tapped from a notification. Waits for
    /// the repo to have the row (a cold launch may deliver the tap before the
    /// list has loaded); if it's not present yet, leaves the id pending so a
    /// later refresh + onAppear can resolve it.
    private func openReminderFromNotification(_ id: UUID?) {
        guard let id else { return }
        guard let match = repo.reminders.first(where: { $0.id == id }) else { return }
        editingReminder = match
        starterPrefill = nil
        isEditorPresented = true
        router.pendingReminderId = nil
    }

    /// Show the pre-prompt primer once, only if the system hasn't been asked
    /// yet. Both solo and paired users get a primer — without it solo users
    /// would hit the bare iOS dialog with no context and tap "Don't Allow",
    /// then wonder why nothing ever fires.
    private func maybeShowNotificationPrimer() async {
        guard !UserDefaults.standard.bool(forKey: primerShownKey) else {
            NotificationCenter.default.post(name: .bondNotificationPrimerResolved, object: nil)
            return
        }
        let status = await UNUserNotificationCenter.current()
            .notificationSettings().authorizationStatus
        guard status == .notDetermined else {
            NotificationCenter.default.post(name: .bondNotificationPrimerResolved, object: nil)
            return
        }
        UserDefaults.standard.set(true, forKey: primerShownKey)
        showNotificationPrimer = true
    }

    /// Everything the user should see: their own reminders (regardless of target)
    /// plus reminders the partner addressed to them.
    private var visibleReminders: [ReminderDTO] {
        guard let me = supabase.currentUserId else { return [] }
        return repo.reminders.filter { $0.authorId == me || $0.targetId == me }
    }

    /// Repeating reminders never leave the active list — completing one only
    /// checks it off for the current period. One-shots drop to Handled.
    private var activeReminders: [ReminderDTO] {
        visibleReminders.filter { $0.repeatsOnSchedule || !isActedOn($0) }
    }

    private var partnerRequests: [ReminderDTO] {
        guard let me = supabase.currentUserId, !pairing.solo else { return [] }
        return sortByNextDate(activeReminders.filter { $0.authorId != me })
    }

    /// Reminders I authored (for me or partner), still active.
    private var myActiveReminders: [ReminderDTO] {
        guard let me = supabase.currentUserId else { return [] }
        return activeReminders.filter { $0.authorId == me }
    }

    private var pastDueReminders: [ReminderDTO] {
        sortByNextDate(myActiveReminders.filter(isPastDue))
    }

    /// Everything active that isn't past due, as one list: dated reminders in
    /// fire order, then undated ("anytime") ones by recency. Each row already
    /// states its own time ("in 3 hours", "tomorrow"), so the old
    /// Today/This week/Later/Anytime buckets only added four headers' worth
    /// of chrome to say what the rows said themselves.
    private var upNextReminders: [ReminderDTO] {
        let dated = sortByNextDate(myActiveReminders.filter {
            !isPastDue($0) && nextDate(for: $0) != nil
        })
        let undated = sortByCreatedDate(myActiveReminders.filter {
            !isPastDue($0) && nextDate(for: $0) == nil
        })
        return dated + undated
    }

    private var handledReminders: [ReminderDTO] {
        sortByCreatedDate(visibleReminders.filter { !$0.repeatsOnSchedule && isActedOn($0) })
    }

    private var composeButton: some View {
        Button {
            editingReminder = nil
            isEditorPresented = true
        } label: {
            Image(systemName: "plus")
                .font(.bond(.title2, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Color.bondAccent, in: Circle())
                .shadow(color: Color.bondAccent.opacity(0.28), radius: 12, x: 0, y: 6)
        }
        .padding(BondSpacing.base)
        .accessibilityLabel("Add reminder")
    }

    /// Insets for the floating hero cards so their soft shadows have room to
    /// breathe instead of clipping against the next row.
    private static let heroCardInsets = EdgeInsets(top: 6, leading: 16, bottom: 10, trailing: 16)

    // Visual hierarchy, top to bottom:
    //   1. One "act now" tier — check-in prompt and partner requests — rendered
    //      as floating elevated cards. At most one element on screen is loud
    //      (the reveal-ready check-in uses the accent gradient).
    //   2. The reminder list itself: at most two sections — "Past due" (the
    //      only tinted header, only when something slipped) and "Up next".
    //      Rows carry their own relative time, so finer date buckets are
    //      redundant chrome.
    //   3. Quiet utility tier: pairing nudge, a one-row link to Handled, and
    //      the templates entry — compact rows that don't compete with the
    //      content above.
    private var list: some View {
        List {
            if let state = checkInCardState {
                Section {
                    NavigationLink {
                        DailyCheckInView()
                    } label: {
                        CheckInPromptCard(state: state, partnerName: partnerName)
                    }
                    .listRowInsets(Self.heroCardInsets)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }

            if !partnerRequests.isEmpty {
                Section {
                    ForEach(partnerRequests) { requestRow($0) }
                } header: {
                    BondSectionHeader(title: "From \(partnerName)")
                }
            }

            if myActiveReminders.isEmpty && partnerRequests.isEmpty {
                Section {
                    MyListEmptyView(
                        partnerName: partnerName,
                        isPaired: !pairing.solo,
                        onAdd: {
                            editingReminder = nil
                            isEditorPresented = true
                        },
                        onBrowseTemplates: { isTemplatesPresented = true }
                    )
                    .listRowBackground(Color.clear)
                }
            }

            if !pastDueReminders.isEmpty {
                Section {
                    ForEach(pastDueReminders) { row($0) }
                        .onDelete { offsets in delete(pastDueReminders, at: offsets) }
                        .bondWarmRow()
                } header: {
                    BondSectionHeader(title: "Past due", tint: .orange)
                }
            }

            if !upNextReminders.isEmpty {
                Section {
                    ForEach(upNextReminders) { row($0) }
                        .onDelete { offsets in delete(upNextReminders, at: offsets) }
                        .bondWarmRow()
                } header: {
                    BondSectionHeader(title: "Up next")
                }
            }

            if !handledReminders.isEmpty {
                Section {
                    NavigationLink {
                        HandledRemindersView()
                    } label: {
                        HStack {
                            Text("Handled")
                                .font(.bond(.subheadline))
                            Spacer()
                            Text("\(handledReminders.count)")
                                .font(.bond(.subheadline))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .bondWarmRow()
                }
            }

            // Quiet utility tier: ordinary grouped rows, same language as the
            // reminders above, so neither entry reads as a marketing card.
            if pairing.solo && !pairingNudgeDismissed {
                Section {
                    PairingNudgeRow(
                        onPair: { isPairingPresented = true },
                        onDismiss: { pairingNudgeDismissed = true }
                    )
                    .bondWarmRow()
                }
            }

            Section {
                TemplatesHomeRow(isPremium: store.isPremium) {
                    isTemplatesPresented = true
                }
                .bondWarmRow()
            }

            // Clearance so the floating compose button never covers the last row.
            Section {
                Color.clear
                    .frame(height: 56)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(BondSpacing.base)
        .bondWarmList()
    }

    private var partnerName: String {
        if let name = pairing.partnerProfile?.displayName, !name.isEmpty {
            return name
        }
        return "Your partner"
    }

    @ViewBuilder
    private func row(_ reminder: ReminderDTO) -> some View {
        let acted = isActedOn(reminder)
        Button {
            editingReminder = reminder
            isEditorPresented = true
        } label: {
            ReminderRow(
                reminder: reminder,
                currentUserId: supabase.currentUserId,
                isActedOn: acted,
                onToggleDone: { toggleDone(reminder) }
            )
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await deleteReminder(reminder) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            if acted {
                Button {
                    Task { await uncompleteReminder(reminder) }
                } label: {
                    Label("Not done", systemImage: "arrow.uturn.backward")
                }
            } else {
                Button {
                    Task { await completeReminder(reminder) }
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .tint(.green)
            }
        }
    }

    private func requestRow(_ reminder: ReminderDTO) -> some View {
        PartnerRequestCard(
            reminder: reminder,
            currentUserId: supabase.currentUserId,
            partnerName: partnerName,
            onEdit: {
                editingReminder = reminder
                isEditorPresented = true
            },
            onDone: { markDone(reminder) }
        )
        .listRowInsets(Self.heroCardInsets)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await deleteReminder(reminder) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func isActedOn(_ reminder: ReminderDTO) -> Bool {
        reminder.isCompleted(in: eventsRepo.events)
    }

    private func toggleDone(_ reminder: ReminderDTO) {
        Task {
            if isActedOn(reminder) {
                await uncompleteReminder(reminder)
            } else {
                await completeReminder(reminder)
            }
        }
    }

    private func nextDate(for reminder: ReminderDTO) -> Date? {
        reminder.trigger?.upcomingFireDate(after: Date.now)
    }

    /// One-time reminder whose fire date has passed.
    private func isPastDue(_ reminder: ReminderDTO) -> Bool {
        guard case .oneTime(let fireAt) = reminder.trigger else { return false }
        return fireAt < Date.now
    }

    private var checkInCardState: CheckInPromptCard.State? {
        guard !pairing.solo else { return nil }
        guard checkIn.todaysQuestion != nil else { return nil }
        if checkIn.myResponse == nil { return .pending }
        if checkIn.partnerResponse == nil { return .awaitingPartner }
        return .readyToReveal
    }

    private func sortByNextDate(_ reminders: [ReminderDTO]) -> [ReminderDTO] {
        reminders.sorted {
            (nextDate(for: $0) ?? .distantFuture) < (nextDate(for: $1) ?? .distantFuture)
        }
    }

    private func sortByCreatedDate(_ reminders: [ReminderDTO]) -> [ReminderDTO] {
        reminders.sorted {
            ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
        }
    }

    private func markDone(_ reminder: ReminderDTO) {
        Task { await completeReminder(reminder) }
    }

    /// Records a handled reminder and may trigger the review funnel after a delay.
    /// Repeating reminders complete per period (done today, back tomorrow).
    private func completeReminder(_ reminder: ReminderDTO) async {
        guard let coupleId = pairing.coupleId else { return }
        // The in-flight guard absorbs double-taps: without it, two quick taps
        // both pass the isActedOn check (the first event hasn't landed yet)
        // and write two completion events — which then makes undo look broken
        // because deleting one still leaves the reminder "done".
        guard !togglingIds.contains(reminder.id), !isActedOn(reminder) else { return }
        togglingIds.insert(reminder.id)
        defer { togglingIds.remove(reminder.id) }
        try? await eventsRepo.createEvent(reminderId: reminder.id, coupleId: coupleId)
        await rescheduleNotifications()
        ReviewPromptTracker.recordPositiveMoment()
        NotificationCenter.default.post(name: .bondPositiveMomentForReview, object: nil)
    }

    /// Undo for a mis-tap: removes the completion covering the current period
    /// and restores any notification the completion suppressed.
    private func uncompleteReminder(_ reminder: ReminderDTO) async {
        guard !togglingIds.contains(reminder.id) else { return }
        togglingIds.insert(reminder.id)
        defer { togglingIds.remove(reminder.id) }
        guard let event = reminder.currentCompletionEvent(in: eventsRepo.events) else { return }
        try? await eventsRepo.deleteEvent(event)
        await rescheduleNotifications()
    }

    private func deleteReminder(_ reminder: ReminderDTO) async {
        try? await repo.delete(reminder)
        await rescheduleNotifications()
    }

    private func rescheduleNotifications() async {
        guard let me = supabase.currentUserId else { return }
        await NotificationScheduler.shared.reschedule(
            forSelfUserId: me, reminders: repo.reminders, events: eventsRepo.events
        )
    }

    private func delete(_ source: [ReminderDTO], at offsets: IndexSet) {
        Task {
            for index in offsets {
                try? await repo.delete(source[index])
            }
            await rescheduleNotifications()
        }
    }
}

/// Full handled history, pushed from the one-row "Handled" link on home so
/// completed reminders stop occupying home-screen real estate.
private struct HandledRemindersView: View {
    @Environment(SupabaseService.self) private var supabase
    @Environment(ReminderRepository.self) private var repo
    @Environment(ReminderEventRepository.self) private var eventsRepo

    @State private var editingReminder: ReminderDTO?

    private var handled: [ReminderDTO] {
        guard let me = supabase.currentUserId else { return [] }
        return repo.reminders
            .filter { $0.authorId == me || $0.targetId == me }
            .filter { !$0.repeatsOnSchedule && $0.isCompleted(in: eventsRepo.events) }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    var body: some View {
        List {
            ForEach(handled) { reminder in
                Button {
                    editingReminder = reminder
                } label: {
                    ReminderRow(
                        reminder: reminder,
                        currentUserId: supabase.currentUserId,
                        isActedOn: true
                    )
                }
                .buttonStyle(.plain)
                .bondWarmRow()
            }
            .onDelete { offsets in
                let source = handled
                Task {
                    for index in offsets {
                        try? await repo.delete(source[index])
                    }
                    if let me = supabase.currentUserId {
                        await NotificationScheduler.shared.reschedule(
                            forSelfUserId: me,
                            reminders: repo.reminders,
                            events: eventsRepo.events
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .bondWarmList()
        .navigationTitle("Handled")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingReminder) { reminder in
            ReminderEditorView(existing: reminder, prefill: nil)
        }
    }
}

/// Floating warm-white card with a hairline and a soft warm shadow — the
/// shared shell for the "act now" tier so home has exactly one card language.
private struct HomeHeroCardBackground: ViewModifier {
    var fill: AnyShapeStyle = AnyShapeStyle(Color.bondCardFill)
    var showsHairline = true

    func body(content: Content) -> some View {
        content
            .padding(BondSpacing.base)
            .background(fill, in: RoundedRectangle(cornerRadius: BondRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BondRadius.card, style: .continuous)
                    .strokeBorder(showsHairline ? Color.bondHairline : .clear, lineWidth: 0.5)
            )
            .shadow(color: .bondShadow, radius: 6, x: 0, y: 3)
    }
}

/// Circular tinted chip behind a card's leading SF Symbol — the consistent
/// "this is an action card" marker across the hero tier.
private struct CardIconChip: View {
    let systemName: String
    var tint: Color = .bondAccent
    var onGradient = false

    var body: some View {
        Image(systemName: systemName)
            .font(.bond(.subheadline, weight: .semibold))
            .foregroundStyle(onGradient ? AnyShapeStyle(.white) : AnyShapeStyle(tint))
            .frame(width: 36, height: 36)
            .background(
                onGradient ? AnyShapeStyle(.white.opacity(0.20)) : AnyShapeStyle(tint.opacity(0.12)),
                in: Circle()
            )
    }
}

private struct PartnerRequestCard: View {
    let reminder: ReminderDTO
    let currentUserId: UUID?
    let partnerName: String
    let onEdit: () -> Void
    let onDone: () -> Void

    private var nextFire: Date? { reminder.trigger?.upcomingFireDate() }
    private var primaryActionTitle: String {
        nextFire == nil ? "Pick a time" : "Reschedule"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BondSpacing.m) {
            HStack(alignment: .top, spacing: BondSpacing.m) {
                CardIconChip(systemName: "sparkles")
                VStack(alignment: .leading, spacing: BondSpacing.xs) {
                    Text("\(partnerName) added this")
                        .font(.bond(.caption, weight: .semibold))
                        .foregroundStyle(Color.bondAccent)
                    Text(reminder.title)
                        .font(.bond(.headline))
                        .foregroundStyle(.primary)
                    if let body = reminder.body, !body.isEmpty {
                        Text(body)
                            .font(.bond(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                    if let next = nextFire {
                        Label(next.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                            .font(.bond(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            HStack(spacing: BondSpacing.s) {
                Button(primaryActionTitle, action: onEdit)
                    .buttonStyle(.borderedProminent)
                    .tint(.bondAccent)
                Button("Handled", action: onDone)
                    .buttonStyle(.bordered)
                    .tint(.bondAccent)
            }
        }
        .modifier(HomeHeroCardBackground())
        .accessibilityElement(children: .combine)
    }
}

private struct CheckInPromptCard: View {
    enum State { case pending, awaitingPartner, readyToReveal }
    let state: State
    let partnerName: String

    private var icon: String {
        switch state {
        case .pending:         "questionmark.bubble.fill"
        case .awaitingPartner: "hourglass"
        case .readyToReveal:   "sparkles"
        }
    }
    private var headline: String {
        switch state {
        case .pending:         "Today's check-in"
        case .awaitingPartner: "Waiting on \(partnerName)"
        case .readyToReveal:   "\(partnerName) answered"
        }
    }
    private var subhead: String {
        switch state {
        case .pending:         "Answer to see \(partnerName)'s reply."
        case .awaitingPartner: "We'll let you know when their answer lands."
        case .readyToReveal:   "Tap to reveal both answers."
        }
    }

    /// Reveal-ready is the one loud element on home: both partners have done
    /// their part and the payoff is a tap away. Everything else stays on the
    /// quiet warm-white shell, with the waiting state desaturated to gray so
    /// "nothing for you to do" also reads that way.
    private var isLoud: Bool { state == .readyToReveal }

    var body: some View {
        HStack(spacing: BondSpacing.m) {
            CardIconChip(
                systemName: icon,
                tint: state == .awaitingPartner ? .secondary : .bondAccent,
                onGradient: isLoud
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.bond(.subheadline, weight: .semibold))
                    .foregroundStyle(isLoud ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                Text(subhead)
                    .font(.bond(.caption))
                    .foregroundStyle(isLoud ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.bond(.caption, weight: .semibold))
                .foregroundStyle(isLoud ? AnyShapeStyle(.white.opacity(0.7)) : AnyShapeStyle(.tertiary))
        }
        .modifier(HomeHeroCardBackground(
            fill: isLoud ? AnyShapeStyle(Color.bondAccentGradient) : AnyShapeStyle(Color.bondCardFill),
            showsHairline: !isLoud
        ))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(headline). \(subhead)")
    }
}

/// Home-screen nudge shown to solo users so pairing isn't buried in Settings.
/// Dismissible (persisted) so it never nags. A plain grouped row in the
/// utility tier at the bottom of the list — the old hairline-outline floating
/// card read as a broken/empty card against the cream wash in light mode.
private struct PairingNudgeRow: View {
    let onPair: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: BondSpacing.m) {
            Button(action: onPair) {
                HStack(spacing: BondSpacing.m) {
                    Image(systemName: "heart.circle.fill")
                        .font(.bond(.title3))
                        .foregroundStyle(Color.bondAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pair with your partner")
                            .font(.bond(.subheadline, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Share reminders and a daily check-in.")
                            .font(.bond(.caption))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: BondSpacing.s)
                    Text("Pair")
                        .font(.bond(.subheadline, weight: .bold))
                        .foregroundStyle(Color.bondAccent)
                }
            }
            .buttonStyle(.plain)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.bond(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(BondSpacing.xs)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}

private struct MyListEmptyView: View {
    let partnerName: String
    let isPaired: Bool
    let onAdd: () -> Void
    let onBrowseTemplates: () -> Void

    private var subtitle: String {
        isPaired
            ? "Add something for you or \(partnerName) — or pick a template below."
            : "Add a reminder — or pick a template below."
    }

    var body: some View {
        VStack(spacing: BondSpacing.base) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 40))
                .foregroundStyle(Color.bondAccent)
            Text("Your list is clear")
                .font(.bond(.title3, weight: .bold))
            Text(subtitle)
                .font(.bond(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add one", action: onAdd)
                .buttonStyle(.borderedProminent)
                .tint(.bondAccent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BondSpacing.xxl)
    }
}

/// Always-visible templates entry point at the bottom of the home list. A
/// plain grouped row — same size and shape as the reminder rows above it —
/// with a small Bond+ badge as the only gating signal for free users. The
/// destination handles its own gating (free users hit the templates preview).
private struct TemplatesHomeRow: View {
    let isPremium: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: BondSpacing.m) {
                Image(systemName: "square.grid.2x2")
                    .font(.bond(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.bondAccent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: BondSpacing.xs) {
                        Text("Reminder templates")
                            .font(.bond(.subheadline, weight: .semibold))
                            .foregroundStyle(.primary)
                        if !isPremium {
                            HStack(spacing: 3) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 8, weight: .bold))
                                Text("Bond+")
                                    .font(.bond(.caption2, weight: .heavy))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, BondSpacing.s)
                            .padding(.vertical, 3)
                            .background(Color.bondAccent, in: Capsule())
                        }
                    }
                    Text("Date nights, long distance, daily affirmations & more")
                        .font(.bond(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.bond(.caption, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isPremium ? "Browse reminder templates" : "Preview reminder templates")
    }
}
