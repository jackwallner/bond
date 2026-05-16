import SwiftUI
import UserNotifications

struct ReminderListView: View {
    @Environment(SupabaseService.self) private var supabase
    @Environment(ReminderRepository.self) private var repo
    @Environment(ReminderEventRepository.self) private var eventsRepo
    @Environment(PairingService.self) private var pairing
    @Environment(PurchasesService.self) private var store

    @State private var isEditorPresented = false
    @State private var isTemplatesPresented = false
    @State private var editingReminder: ReminderDTO?
    @State private var listFilter: ReminderFilter = .all
    @State private var showNotificationPrimer = false
    @State private var starterPrefill: StarterChip?

    private let primerShownKey = "hasShownNotificationPrimer"

    enum ReminderFilter: String, CaseIterable {
        case all, forMe
        var title: String {
            switch self {
            case .all: "All"
            case .forMe: "For Me"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if repo.reminders.isEmpty {
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
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            isTemplatesPresented = true
                        } label: {
                            Image(systemName: "square.grid.2x2")
                        }
                        Button {
                            editingReminder = nil
                            isEditorPresented = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
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
                await repo.subscribeRealtime()
                await NotificationScheduler.shared.reschedule(
                    forSelfUserId: supabase.currentUserId ?? UUID(),
                    reminders: repo.reminders
                )
                await maybeShowNotificationPrimer()
            }
        }
    }

    /// Show the pre-prompt primer once, only if the system hasn't been asked
    /// yet. Solo users see it when they first open the editor instead.
    private func maybeShowNotificationPrimer() async {
        guard !pairing.solo else { return }
        guard !UserDefaults.standard.bool(forKey: primerShownKey) else { return }
        let status = await UNUserNotificationCenter.current()
            .notificationSettings().authorizationStatus
        guard status == .notDetermined else { return }
        UserDefaults.standard.set(true, forKey: primerShownKey)
        showNotificationPrimer = true
    }

    private var filteredReminders: [ReminderDTO] {
        guard let me = supabase.currentUserId else { return repo.reminders }
        switch listFilter {
        case .all:
            return repo.reminders
        case .forMe:
            return repo.reminders.filter { $0.targetId == me }
        }
    }

    private var grouped: (upcoming: [ReminderDTO], past: [ReminderDTO]) {
        let now = Date.now
        var upcoming: [ReminderDTO] = []
        var past: [ReminderDTO] = []
        for r in filteredReminders {
            // upcomingFireDate advances recurring reminders forward, so a daily
            // reminder anchored last month still appears in Upcoming.
            if let next = r.trigger?.upcomingFireDate(after: now), next >= now {
                upcoming.append(r)
            } else {
                past.append(r)
            }
        }
        return (upcoming, past)
    }

    private var list: some View {
        List {
            if !pairing.solo && supabase.currentUserId != nil {
                Section {
                    Picker("Show", selection: $listFilter) {
                        ForEach(ReminderFilter.allCases, id: \.self) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            }

            let g = grouped

            if filteredReminders.isEmpty {
                Section {
                    FilteredEmptyView { listFilter = .all }
                }
            }

            if !g.upcoming.isEmpty {
                Section("Upcoming") {
                    ForEach(g.upcoming) { row($0) }
                        .onDelete { offsets in delete(g.upcoming, at: offsets) }
                }
            }
            if !g.past.isEmpty {
                Section("Past") {
                    ForEach(g.past) { row($0) }
                        .onDelete { offsets in delete(g.past, at: offsets) }
                }
            }
        }
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
                    Task {
                        guard let coupleId = pairing.coupleId else { return }
                        try? await eventsRepo.createEvent(
                            reminderId: reminder.id, coupleId: coupleId
                        )
                        await NotificationScheduler.shared.reschedule(
                            forSelfUserId: supabase.currentUserId ?? UUID(),
                            reminders: repo.reminders
                        )
                    }
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .tint(.green)
            }
        }
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
