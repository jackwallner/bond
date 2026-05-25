import SwiftUI

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
                } footer: {
                    Text("You'll get a heads-up 1 week before, the day before, and on the day at 9 AM. The next milestone also shows on your home-screen widget.")
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.bond(.footnote))
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
