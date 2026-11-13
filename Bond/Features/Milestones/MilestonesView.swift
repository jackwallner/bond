import SwiftUI

struct MilestonesView: View {
    @Environment(MilestonesService.self) private var milestones
    @State private var isEditorPresented = false
    @State private var editing: MilestoneDTO?

    var body: some View {
        NavigationStack {
            Group {
                if milestones.milestones.isEmpty {
                    ContentUnavailableView {
                        Label("No milestones yet", systemImage: "calendar.badge.plus")
                    } description: {
                        Text("Add your anniversary, birthdays, or any date worth remembering. Little Gestures shows the next one on your widget and pings you a week before, the day before, and on the day.")
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Milestones")
            .columnTitle()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = nil
                        isEditorPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .unfoldedSheet(isPresented: $isEditorPresented) {
                MilestoneEditorView(existing: editing)
            }
            .task { await milestones.refresh() }
        }
    }

    private var list: some View {
        List {
            ForEach(milestones.milestones.sorted { $0.nextOccurrence() < $1.nextOccurrence() }) { m in
                Button {
                    editing = m
                    isEditorPresented = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: m.kind == "birthday" ? "gift.fill" : "heart.fill")
                            .foregroundStyle(Color.bondAccent)
                            .frame(width: 28)
                        VStack(alignment: .leading) {
                            Text(m.label ?? MilestoneDTO.kindTitle(m.kind))
                                .font(.bond(.headline))
                            Text(m.nextOccurrence(), style: .date)
                                .font(.bond(.caption))
                                .foregroundStyle(.bondTextSecondary)
                        }
                        Spacer()
                        let days = m.daysUntilNextOccurrence()
                        Text("\(days)d")
                            .font(.bond(.callout).monospacedDigit())
                            .foregroundStyle(.bondTextSecondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                Task {
                    let sorted = milestones.milestones.sorted { $0.nextOccurrence() < $1.nextOccurrence() }
                    for i in offsets { try? await milestones.delete(sorted[i]) }
                }
            }
            .bondWarmRow()
        }
        .bondWarmList()
    }
}
