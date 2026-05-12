import SwiftUI

struct ReminderListView: View {
    @Environment(SupabaseService.self) private var supabase
    @Environment(ReminderRepository.self) private var repo

    @State private var isEditorPresented = false
    @State private var editingReminder: ReminderDTO?

    var body: some View {
        NavigationStack {
            Group {
                if repo.reminders.isEmpty {
                    ContentUnavailableView {
                        Label("No reminders yet", systemImage: "heart.text.square")
                    } description: {
                        Text("Tap + to add your first reminder for your partner or yourself.")
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Bond")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingReminder = nil
                        isEditorPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isEditorPresented) {
                ReminderEditorView(existing: editingReminder)
            }
            .refreshable {
                await repo.refresh()
            }
            .task {
                await repo.refresh()
                await repo.subscribeRealtime()
                await NotificationScheduler.shared.reschedule(
                    forSelfUserId: supabase.currentUserId ?? UUID(),
                    reminders: repo.reminders
                )
            }
        }
    }

    private var grouped: (upcoming: [ReminderDTO], past: [ReminderDTO]) {
        let now = Date.now
        var upcoming: [ReminderDTO] = []
        var past: [ReminderDTO] = []
        for r in repo.reminders {
            if let next = r.trigger?.nextFireDate, next < now {
                past.append(r)
            } else {
                upcoming.append(r)
            }
        }
        return (upcoming, past)
    }

    private var list: some View {
        List {
            let g = grouped

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

    private func row(_ reminder: ReminderDTO) -> some View {
        Button {
            editingReminder = reminder
            isEditorPresented = true
        } label: {
            ReminderRow(reminder: reminder, currentUserId: supabase.currentUserId)
        }
        .buttonStyle(.plain)
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

private struct ReminderRow: View {
    let reminder: ReminderDTO
    let currentUserId: UUID?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: reminder.loveLanguage.symbolName)
                .foregroundStyle(reminder.loveLanguage.tint)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title)
                    .font(.headline)
                    .lineLimit(2)
                if let body = reminder.body, !body.isEmpty {
                    Text(body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    if let next = reminder.trigger?.nextFireDate {
                        Text(next, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if reminder.triggerType == "recurring",
                       let rrule = reminder.rrule,
                       let preset = RecurrencePreset(rrule: rrule) {
                        Text(preset.title)
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.gray.opacity(0.15), in: Capsule())
                    }
                    if reminder.targetId != currentUserId {
                        Text("for partner")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(reminder.loveLanguage.tint.opacity(0.15), in: Capsule())
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
