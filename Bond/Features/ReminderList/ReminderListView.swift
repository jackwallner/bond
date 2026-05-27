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
    @State private var starterPrefill: StarterChip?
    @State private var hasLoadedOnce = false
    @State private var showAllHandled = false

    private let primerShownKey = "hasShownNotificationPrimer"
    private let handledRecentDays = 7

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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        BondMoreView()
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                }
            }
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
            .sheet(isPresented: $showNotificationPrimer) {
                NotificationPrimerSheet {
                    Task { await NotificationScheduler.shared.requestAuthorizationIfNeeded() }
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
                await NotificationScheduler.shared.reschedule(
                    forSelfUserId: supabase.currentUserId ?? UUID(),
                    reminders: repo.reminders
                )
                await maybeShowNotificationPrimer()
            }
            .onChange(of: router.pendingReminderId) { _, id in
                openReminderFromNotification(id)
            }
            .onAppear { openReminderFromNotification(router.pendingReminderId) }
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
        guard !UserDefaults.standard.bool(forKey: primerShownKey) else { return }
        let status = await UNUserNotificationCenter.current()
            .notificationSettings().authorizationStatus
        guard status == .notDetermined else { return }
        UserDefaults.standard.set(true, forKey: primerShownKey)
        showNotificationPrimer = true
    }

    /// Everything the user should see: their own reminders (regardless of target)
    /// plus reminders the partner addressed to them.
    private var visibleReminders: [ReminderDTO] {
        guard let me = supabase.currentUserId else { return [] }
        return repo.reminders.filter { $0.authorId == me || $0.targetId == me }
    }

    private var activeReminders: [ReminderDTO] {
        visibleReminders.filter { !isActedOn($0) }
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

    private var todayReminders: [ReminderDTO] {
        sortByNextDate(myActiveReminders.filter {
            guard !isPastDue($0), let next = nextDate(for: $0) else { return false }
            return Calendar.current.isDateInToday(next)
        })
    }

    private var weekReminders: [ReminderDTO] {
        let calendar = Calendar.current
        let now = Date.now
        let cutoff = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        return sortByNextDate(myActiveReminders.filter {
            guard !isPastDue($0), let next = nextDate(for: $0) else { return false }
            return !calendar.isDateInToday(next) && next <= cutoff
        })
    }

    private var laterReminders: [ReminderDTO] {
        let cutoff = Calendar.current.date(byAdding: .day, value: 7, to: Date.now) ?? Date.now
        return sortByNextDate(myActiveReminders.filter {
            guard !isPastDue($0), let next = nextDate(for: $0) else { return false }
            return next > cutoff
        })
    }

    private var anytimeReminders: [ReminderDTO] {
        sortByCreatedDate(myActiveReminders.filter {
            !isPastDue($0) && nextDate(for: $0) == nil
        })
    }

    private var handledReminders: [ReminderDTO] {
        sortByCreatedDate(visibleReminders.filter { isActedOn($0) })
    }

    private var recentHandledReminders: [ReminderDTO] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -handledRecentDays, to: Date.now) ?? Date.now
        return handledReminders.filter { ($0.createdAt ?? .distantPast) >= cutoff }
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

    private var list: some View {
        List {
            if let state = checkInCardState {
                Section {
                    NavigationLink {
                        DailyCheckInView()
                    } label: {
                        CheckInPromptCard(state: state, partnerName: partnerName)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }

            if !partnerRequests.isEmpty {
                Section {
                    ForEach(partnerRequests) { requestRow($0) }
                } header: {
                    Text("\(partnerName) added")
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
                Section("Past due") {
                    ForEach(pastDueReminders) { row($0) }
                        .onDelete { offsets in delete(pastDueReminders, at: offsets) }
                }
            }

            if !todayReminders.isEmpty {
                Section("Today") {
                    ForEach(todayReminders) { row($0) }
                        .onDelete { offsets in delete(todayReminders, at: offsets) }
                }
            }

            if !weekReminders.isEmpty {
                Section("This week") {
                    ForEach(weekReminders) { row($0) }
                        .onDelete { offsets in delete(weekReminders, at: offsets) }
                }
            }

            if !laterReminders.isEmpty {
                Section("Later") {
                    ForEach(laterReminders) { row($0) }
                        .onDelete { offsets in delete(laterReminders, at: offsets) }
                }
            }

            if !anytimeReminders.isEmpty {
                Section("Anytime") {
                    ForEach(anytimeReminders) { row($0) }
                        .onDelete { offsets in delete(anytimeReminders, at: offsets) }
                }
            }

            handledSection

            Section {
                TemplatesHomePitch { isTemplatesPresented = true }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 80, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var handledSection: some View {
        let recent = recentHandledReminders
        let all = handledReminders
        if !all.isEmpty {
            let shown = showAllHandled ? all : recent
            Section {
                ForEach(shown) { row($0) }
                    .onDelete { offsets in delete(shown, at: offsets) }
                if all.count > recent.count {
                    Button(showAllHandled ? "Show recent only" : "Show all \(all.count) handled") {
                        showAllHandled.toggle()
                    }
                    .font(.bond(.footnote))
                }
            } header: {
                Text(showAllHandled ? "Handled" : "Handled · last \(handledRecentDays) days")
            }
        }
    }

    private var partnerName: String {
        if let name = pairing.partnerProfile?.displayName, !name.isEmpty {
            return name
        }
        return "Your partner"
    }

    @ViewBuilder
    private func row(_ reminder: ReminderDTO) -> some View {
        Button {
            editingReminder = reminder
            isEditorPresented = true
        } label: {
            let acted = eventsRepo.events
                .filter { $0.reminderId == reminder.id && $0.actedAt != nil }
                .count > 0
            ReminderRow(
                reminder: reminder,
                currentUserId: supabase.currentUserId,
                isActedOn: acted
            )
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { try? await repo.delete(reminder) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            let hasEvent = eventsRepo.events
                .contains { $0.reminderId == reminder.id && $0.actedAt != nil }
            if !hasEvent {
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
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { try? await repo.delete(reminder) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func isActedOn(_ reminder: ReminderDTO) -> Bool {
        eventsRepo.events.contains { $0.reminderId == reminder.id && $0.actedAt != nil }
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
    private func completeReminder(_ reminder: ReminderDTO) async {
        guard let coupleId = pairing.coupleId else { return }
        let alreadyDone = eventsRepo.events.contains { $0.reminderId == reminder.id }
        guard !alreadyDone else { return }
        try? await eventsRepo.createEvent(reminderId: reminder.id, coupleId: coupleId)
        await NotificationScheduler.shared.reschedule(
            forSelfUserId: supabase.currentUserId ?? UUID(),
            reminders: repo.reminders
        )
        ReviewPromptTracker.recordPositiveMoment()
        NotificationCenter.default.post(name: .bondPositiveMomentForReview, object: nil)
    }

    private func delete(_ source: [ReminderDTO], at offsets: IndexSet) {
        Task {
            for index in offsets {
                try? await repo.delete(source[index])
            }
            if let me = supabase.currentUserId {
                await NotificationScheduler.shared.reschedule(
                    forSelfUserId: me, reminders: repo.reminders
                )
            }
        }
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
                Image(systemName: "sparkles")
                    .font(.bond(.title3))
                    .foregroundStyle(Color.bondAccent)
                    .frame(width: 28, height: 28)
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
        .padding(BondSpacing.base)
        .background(Color.bondAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: BondRadius.hero))
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

    var body: some View {
        HStack(spacing: BondSpacing.m) {
            Image(systemName: icon)
                .font(.bond(.title2))
                .foregroundStyle(Color.bondAccent)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.bond(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subhead)
                    .font(.bond(.caption))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.bond(.caption, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(BondSpacing.base)
        .background(Color.bondAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: BondRadius.hero))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(headline). \(subhead)")
    }
}

private struct MyListEmptyView: View {
    let partnerName: String
    let isPaired: Bool
    let onAdd: () -> Void
    let onBrowseTemplates: () -> Void

    private var subtitle: String {
        isPaired
            ? "Add something for you or \(partnerName), or start from a template."
            : "Add a reminder, or start from a template."
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
            HStack(spacing: BondSpacing.s) {
                Button("Add one", action: onAdd)
                    .buttonStyle(.borderedProminent)
                    .tint(.bondAccent)
                Button("Templates", action: onBrowseTemplates)
                    .buttonStyle(.bordered)
                    .tint(.bondAccent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BondSpacing.xxl)
    }
}

/// Always-visible templates entry point that lives at the bottom of the home
/// list. Shows a blurred peek at the available template groups and a CTA so
/// users discover packs without hunting in a toolbar. The destination handles
/// its own gating (free users hit the templates paywall preview).
private struct TemplatesHomePitch: View {
    let onTap: () -> Void

    private var previewGroups: [ReminderTemplateGroup] {
        Array(ReminderTemplateStore.groups.prefix(3))
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                HStack(spacing: BondSpacing.s) {
                    ForEach(previewGroups) { group in
                        VStack(spacing: BondSpacing.xs) {
                            Image(systemName: group.icon)
                                .font(.bond(.title2))
                                .foregroundStyle(.pink)
                            Text(group.title)
                                .font(.bond(.caption, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(group.subtitle)
                                .font(.bond(.caption2))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BondSpacing.base)
                        .padding(.horizontal, BondSpacing.s)
                        .background(Color.bondCardFill, in: RoundedRectangle(cornerRadius: BondRadius.inline))
                    }
                }
                .padding(BondSpacing.s)
                .blur(radius: 5)
                .accessibilityHidden(true)

                VStack(spacing: BondSpacing.xs) {
                    Image(systemName: "square.grid.2x2")
                        .font(.bond(.title3))
                        .foregroundStyle(Color.bondAccent)
                    Text("Reminder templates")
                        .font(.bond(.subheadline, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Packs for date nights, long distance, daily affirmations, and more.")
                        .font(.bond(.caption))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Browse templates →")
                        .font(.bond(.footnote, weight: .bold))
                        .foregroundStyle(Color.bondAccent)
                        .padding(.top, 2)
                }
                .padding(BondSpacing.base)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: BondRadius.hero))
                .padding(BondSpacing.m)
            }
            .frame(maxWidth: .infinity)
            .background(Color.bondAccent.opacity(0.06), in: RoundedRectangle(cornerRadius: BondRadius.hero))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Browse reminder templates")
    }
}
