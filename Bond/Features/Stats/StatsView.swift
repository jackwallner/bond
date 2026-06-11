import Charts
import SwiftUI

struct StatsView: View {
    @Environment(ReminderRepository.self) private var repo
    @Environment(ReminderEventRepository.self) private var eventsRepo
    @Environment(PurchasesService.self) private var store
    @State private var isPaywallPresented = false

    private var analyzer: LoveLanguageAnalyzer {
        LoveLanguageAnalyzer(reminders: repo.reminders, events: eventsRepo.events)
    }

    var body: some View {
        NavigationStack {
            Group {
                if repo.reminders.isEmpty {
                    ContentUnavailableView(
                        "No data yet",
                        systemImage: "chart.bar.xaxis",
                        description: Text("Create reminders and mark them done to see your relationship analytics.")
                    )
                } else if !store.isPremium {
                    teaser
                } else {
                    content
                }
            }
            .navigationTitle("Insights")
            .paywallSheet(isPresented: $isPaywallPresented)
            .task { await eventsRepo.refresh() }
        }
    }

    private var teaser: some View {
        let a = analyzer
        return Form {
            Section {
                streakSection(a: a)
            }
            .bondWarmRow()

            Section {
                BondUnlockCard(
                    icon: "chart.bar.xaxis.ascending",
                    headline: "Unlock the full picture",
                    subhead: "Bond+ opens up your love-language balance, weekly trends, and personalized insights.",
                    isPaywallPresented: $isPaywallPresented,
                    outerPadding: true
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .bondWarmList()
    }

    private var content: some View {
        let a = analyzer
        let counts = a.reminderCounts()
        let total = counts.map(\.1).reduce(0, +)

        return Form {
            // Streak section
            Section {
                streakSection(a: a)
            }
            .bondWarmRow()

            // Balance score
            Section {
                balanceSection(a: a)
            } header: {
                BondSectionHeader(title: "Balance score")
            }
            .bondWarmRow()

            // Distribution chart
            Section {
                Chart(counts, id: \.0) { item in
                    BarMark(
                        x: .value("Count", item.1),
                        y: .value("Language", item.0.title)
                    )
                    .foregroundStyle(item.0.tint)
                    .annotation(position: .trailing) {
                        Text("\(item.1)").font(.bond(.caption2)).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 220)

                // Mini completion bars
                let completionRates = a.completionRates()
                ForEach(completionRates, id: \.0) { lang, rate in
                    HStack {
                        Image(systemName: lang.symbolName)
                            .foregroundStyle(lang.tint)
                            .frame(width: 24)
                        Text(lang.title)
                            .font(.bond(.caption))
                        Spacer()
                        Text("\(Int(rate))%")
                            .font(.bond(.caption).monospacedDigit())
                            .foregroundStyle(.secondary)
                        ProgressView(value: rate, total: 100)
                            .tint(lang.tint)
                            .frame(width: 60)
                    }
                }
            } header: {
                BondSectionHeader(title: "Love language distribution")
            }
            .bondWarmRow()

            // Trends chart
            let trends = a.weeklyTrends()
            if !trends.isEmpty {
                Section {
                    Chart(trends) { week in
                        ForEach(week.counts, id: \.0) { lang, count in
                            BarMark(
                                x: .value("Week", week.weekStart, unit: .weekOfYear),
                                y: .value("Actions", count)
                            )
                            .foregroundStyle(lang.tint)
                            .position(by: .value("Language", lang.title))
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        }
                    }
                    .frame(height: 200)
                } header: {
                    BondSectionHeader(title: "Weekly activity")
                }
                .bondWarmRow()
            }

            // Insights
            let insights = a.insights()
            if !insights.isEmpty {
                Section {
                    ForEach(insights, id: \.self) { insight in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .font(.bond(.caption))
                                .foregroundStyle(.yellow)
                            Text(insight)
                                .font(.bond(.subheadline))
                        }
                    }
                } header: {
                    BondSectionHeader(title: "Insights")
                }
                .bondWarmRow()
            }

            // Summary
            Section {
                summarySection(a: a, total: total)
            } header: {
                BondSectionHeader(title: "Summary")
            }
            .bondWarmRow()
        }
        .bondWarmList()
    }

    private func streakSection(a: LoveLanguageAnalyzer) -> some View {
        let current = a.currentStreak()
        let longest = a.longestStreak()
        return HStack {
            VStack(alignment: .center, spacing: 4) {
                Text("\(current)")
                    .font(.bond(.title, weight: .bold))
                    .foregroundStyle(.pink)
                Text("day streak")
                    .font(.bond(.caption))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 40)

            VStack(alignment: .center, spacing: 4) {
                Text("\(longest)")
                    .font(.bond(.title, weight: .bold))
                    .foregroundStyle(.orange)
                Text("best streak")
                    .font(.bond(.caption))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 40)

            VStack(alignment: .center, spacing: 4) {
                Text("\(Int(a.completionRate()))%")
                    .font(.bond(.title, weight: .bold))
                    .foregroundStyle(.green)
                Text("completion")
                    .font(.bond(.caption))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
    }

    private func balanceSection(a: LoveLanguageAnalyzer) -> some View {
        let score = a.balanceScore()
        return VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 10)
                    .frame(width: 80, height: 80)
                Circle()
                    .trim(from: 0, to: score / 100)
                    .stroke(score > 60 ? .green : score > 30 ? .orange : .red,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                Text("\(Int(score))")
                    .font(.bond(.title2, weight: .bold))
            }

            if let most = a.mostUsed() {
                HStack {
                    Text("Most: ")
                        .font(.bond(.caption))
                        .foregroundStyle(.secondary)
                    Text(most.0.title)
                        .font(.bond(.caption, weight: .bold))
                    Image(systemName: most.0.symbolName)
                        .font(.bond(.caption))
                        .foregroundStyle(most.0.tint)
                }
            }

            if let neglected = a.mostNeglected() {
                HStack {
                    Text("Needs attention: ")
                        .font(.bond(.caption))
                        .foregroundStyle(.secondary)
                    Text(neglected.0.title)
                        .font(.bond(.caption, weight: .bold))
                    Image(systemName: neglected.0.symbolName)
                        .font(.bond(.caption))
                        .foregroundStyle(neglected.0.tint)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func summarySection(a: LoveLanguageAnalyzer, total: Int) -> some View {
        Group {
            LabeledContent("Total reminders", value: "\(total)")
            LabeledContent("For partner", value: "\(repo.reminders.filter { $0.authorId != $0.targetId }.count)")
            LabeledContent("Recurring", value: "\(repo.reminders.filter { $0.triggerType == "recurring" }.count)")
            LabeledContent("Total actions", value: "\(eventsRepo.events.count)")
            LabeledContent("Actions completed", value: "\(eventsRepo.actedCount)")
        }
    }
}
