import SwiftUI

struct SuggestView: View {
    @Environment(SupabaseService.self) private var supabase
    @Environment(PairingService.self) private var pairing
    @Environment(PurchasesService.self) private var store
    @Environment(AIService.self) private var ai
    @Environment(ReminderRepository.self) private var repo
    @Environment(\.dismiss) private var dismiss

    @State private var suggestions: [AISuggestion] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var inserting: Set<String> = []
    @State private var isPaywallPresented = false

    var body: some View {
        NavigationStack {
            Group {
                if !store.isPremium {
                    gate
                } else if isLoading {
                    ProgressView("Thinking…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if suggestions.isEmpty {
                    ContentUnavailableView(
                        "No suggestions yet",
                        systemImage: "sparkles",
                        description: Text("Tap refresh to ask Bond for ideas tuned to your last 30 days.")
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Suggestions")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading || !store.isPremium)
                }
            }
            .sheet(isPresented: $isPaywallPresented) {
                PaywallView()
            }
            .task {
                if store.isPremium && suggestions.isEmpty {
                    await load()
                }
            }
        }
    }

    private var gate: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 56))
                .foregroundStyle(.pink)
            Text("AI suggestions are premium")
                .font(.headline)
            Text("Bond reads the last 30 days of your reminders and proposes five new ones aimed at the love languages you've been quiet on.")
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
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            Section {
                ForEach(suggestions) { suggestion in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: suggestion.loveLanguage.symbolName)
                                .foregroundStyle(suggestion.loveLanguage.tint)
                            Text(suggestion.loveLanguage.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(suggestion.title).font(.headline)
                        Text(suggestion.rationale)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Spacer()
                            if inserting.contains(suggestion.id) {
                                ProgressView().controlSize(.small)
                            } else {
                                Button("Add reminder") {
                                    Task { await add(suggestion) }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func load() async {
        guard let coupleId = pairing.coupleId else {
            errorMessage = "Not paired yet."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            suggestions = try await ai.suggest(coupleId: coupleId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func add(_ suggestion: AISuggestion) async {
        guard let me = supabase.currentUserId,
              let coupleId = pairing.coupleId else { return }
        inserting.insert(suggestion.id)
        defer { inserting.remove(suggestion.id) }

        let reminder = ReminderDTO(
            id: UUID(),
            coupleId: coupleId,
            authorId: me,
            targetId: me,
            title: suggestion.title,
            body: nil,
            loveLanguage: suggestion.loveLanguage,
            triggerType: "one_time",
            fireAt: Calendar.current.date(byAdding: .day, value: 1, to: .now),
            rrule: nil,
            geofence: nil,
            windowStart: nil,
            windowEnd: nil,
            status: "scheduled",
            surpriseHiddenFromPartner: false,
            createdAt: nil
        )
        do {
            try await repo.upsert(reminder)
            suggestions.removeAll { $0.id == suggestion.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
