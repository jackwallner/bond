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
            .sheet(isPresented: $isPaywallPresented) {
                PaywallView()
            }
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

struct MilestoneEditorView: View {
    @Environment(MilestonesService.self) private var service
    @Environment(PairingService.self) private var pairing
    @Environment(\.dismiss) private var dismiss

    var existing: MilestoneDTO?

    @State private var label = ""
    @State private var kind = "anniversary"
    @State private var date = Date()
    @State private var recur = true
    @State private var errorMessage: String?

    private let kinds = ["anniversary", "birthday", "custom"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Label (e.g. \"Our anniversary\")", text: $label)
                    Picker("Kind", selection: $kind) {
                        ForEach(kinds, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Toggle("Repeat yearly", isOn: $recur)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle(existing == nil ? "New milestone" : "Edit milestone")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                }
            }
            .onAppear(perform: hydrate)
        }
    }

    private func hydrate() {
        guard let existing else { return }
        label = existing.label ?? ""
        kind = existing.kind
        date = existing.date
        recur = existing.recur
    }

    private func save() async {
        guard let coupleId = pairing.coupleId else {
            errorMessage = "Not paired."
            return
        }
        let draft = MilestoneDTO(
            id: existing?.id ?? UUID(),
            coupleId: coupleId,
            kind: kind,
            label: label.isEmpty ? nil : label,
            date: date,
            recur: recur,
            createdAt: existing?.createdAt
        )
        do {
            try await service.upsert(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
