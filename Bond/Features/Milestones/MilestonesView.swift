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
                        Label("No milestones", systemImage: "calendar.badge.plus")
                    } description: {
                        Text("Add your anniversary, birthdays, or any date worth remembering.")
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Milestones")
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
            .sheet(isPresented: $isEditorPresented) {
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
                            .foregroundStyle(.pink)
                            .frame(width: 28)
                        VStack(alignment: .leading) {
                            Text(m.label ?? m.kind.capitalized)
                                .font(.bond(.headline))
                            Text(m.nextOccurrence(), style: .date)
                                .font(.bond(.caption))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        let days = max(0, Calendar.current.dateComponents([.day], from: .now, to: m.nextOccurrence()).day ?? 0)
                        Text("\(days)d")
                            .font(.bond(.callout).monospacedDigit())
                            .foregroundStyle(.secondary)
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
        }
    }
}
