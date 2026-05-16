import SwiftUI

struct MilestonesView: View {
    @Environment(MilestonesService.self) private var milestones
    @Environment(PurchasesService.self) private var store
    @State private var isEditorPresented = false
    @State private var editing: MilestoneDTO?
    @State private var isPaywallPresented = false

    var body: some View {
        NavigationStack {
            Group {
                if !store.isPremium {
                    premiumGate
                } else if milestones.milestones.isEmpty {
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
                if store.isPremium {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            editing = nil
                            isEditorPresented = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $isEditorPresented) {
                MilestoneEditorView(existing: editing)
            }
            .paywallSheet(isPresented: $isPaywallPresented)
            .task { await milestones.refresh() }
        }
    }

    private var premiumGate: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 56))
                .foregroundStyle(.pink)
            Text("Milestones is a premium feature")
                .font(.headline)
            Text("Track anniversaries, birthdays, and other dates that matter — with a countdown widget on your home screen.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Unlock Premium") { isPaywallPresented = true }
                .buttonStyle(.borderedProminent)
        }
        .padding()
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
                                .font(.headline)
                            Text(m.nextOccurrence(), style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        let days = max(0, Calendar.current.dateComponents([.day], from: .now, to: m.nextOccurrence()).day ?? 0)
                        Text("\(days)d")
                            .font(.callout.monospacedDigit())
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
