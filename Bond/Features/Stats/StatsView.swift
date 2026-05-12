import Charts
import SwiftUI

struct StatsView: View {
    @Environment(ReminderRepository.self) private var repo
    @Environment(PurchasesService.self) private var store
    @State private var isPaywallPresented = false

    var body: some View {
        NavigationStack {
            Group {
                if !store.isPremium {
                    gate
                } else if repo.reminders.isEmpty {
                    ContentUnavailableView(
                        "No data yet",
                        systemImage: "chart.bar.xaxis",
                        description: Text("Create reminders to see your love-language balance.")
                    )
                } else {
                    content
                }
            }
            .navigationTitle("Stats")
            .sheet(isPresented: $isPaywallPresented) {
                PaywallView()
            }
        }
    }

    private var gate: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 56))
                .foregroundStyle(.pink)
            Text("Stats is a premium feature")
                .font(.headline)
            Text("See which love languages you favor and which ones to dial up.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Unlock Premium") { isPaywallPresented = true }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var counts: [(LoveLanguage, Int)] {
        var dict: [LoveLanguage: Int] = [:]
        for r in repo.reminders { dict[r.loveLanguage, default: 0] += 1 }
        return LoveLanguage.allCases.map { ($0, dict[$0] ?? 0) }
    }

    private var content: some View {
        Form {
            Section("Distribution") {
                Chart(counts, id: \.0) { item in
                    BarMark(
                        x: .value("Count", item.1),
                        y: .value("Language", item.0.title)
                    )
                    .foregroundStyle(item.0.tint)
                    .annotation(position: .trailing) {
                        Text("\(item.1)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 220)
            }

            Section("Totals") {
                LabeledContent("Total reminders", value: "\(repo.reminders.count)")
                LabeledContent(
                    "For partner",
                    value: "\(repo.reminders.filter { $0.authorId != $0.targetId }.count)"
                )
                LabeledContent(
                    "Recurring",
                    value: "\(repo.reminders.filter { $0.triggerType == "recurring" }.count)"
                )
            }
        }
    }
}
