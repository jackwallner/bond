import Charts
import SwiftUI

struct StatsView: View {
    @Environment(ReminderRepository.self) private var repo
    @Environment(ReminderEventRepository.self) private var eventsRepo
    @Environment(PurchasesService.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
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
                    headline: String(localized: "Unlock the full picture"),
                    subhead: String(localized: "Little Gestures+ opens up your love-language balance, weekly trends, and personalized insights."),
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
                BondSectionHeader(title: String(localized: "Balance score"))
            } footer: {
                Text("How evenly your reminders cover the five love languages. 100 means a perfectly even spread; a low score means most of your reminders lean on one or two languages.")
                    .font(.bond(.footnote))
                    .foregroundStyle(.bondTextSecondary)
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
                        Text("\(item.1)").font(.bond(.caption2)).foregroundStyle(.bondTextSecondary)
                    }
                }
                .frame(height: 220)
            } header: {
                BondSectionHeader(title: String(localized: "Reminders per love language"))
            }
            .bondWarmRow()

            // Follow-through: completed vs. due, last 7 days
            followThroughSection(a: a)

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
                    BondSectionHeader(title: String(localized: "Weekly activity"))
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
                    BondSectionHeader(title: String(localized: "Insights"))
                }
                .bondWarmRow()
            }

            // Summary
            Section {
                summarySection(a: a, total: total)
            } header: {
                BondSectionHeader(title: String(localized: "Summary"))
            }
            .bondWarmRow()
        }
        .bondWarmList()
    }

    /// "Did I actually do the things?" - completed vs. due over the last
    /// week, per repeating reminder, with the per-language split below.
    @ViewBuilder
    private func followThroughSection(a: LoveLanguageAnalyzer) -> some View {
        let items = a.followThrough()
        let byLanguage = a.completionByLanguage().filter { $0.expected > 0 }

        Section {
            if items.isEmpty && byLanguage.isEmpty {
                Text("Mark reminders done (tap the circle on a reminder) and your follow-through shows up here.")
                    .font(.bond(.footnote))
                    .foregroundStyle(.bondTextSecondary)
            } else {
                ForEach(items) { item in
                    HStack(spacing: BondSpacing.m) {
                        Image(systemName: item.reminder.loveLanguage.symbolName)
                            .foregroundStyle(item.reminder.loveLanguage.tint)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.reminder.title)
                                .font(.bond(.subheadline))
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                            ProgressView(
                                value: Double(item.completed),
                                total: Double(max(item.expected, 1))
                            )
                            .tint(item.reminder.loveLanguage.tint)
                        }
                        Text("\(item.completed) of \(item.expected)")
                            .font(.bond(.subheadline).monospacedDigit())
                            .foregroundStyle(.bondTextSecondary)
                            .fixedSize()
                    }
                }
                ForEach(byLanguage, id: \.0) { lang, expected, completed in
                    HStack(spacing: BondSpacing.m) {
                        Text(lang.title)
                            .font(.bond(.caption))
                            .foregroundStyle(.bondTextSecondary)
                        Spacer()
                        Text("\(completed) of \(expected) done")
                            .font(.bond(.caption).monospacedDigit())
                            .foregroundStyle(.bondTextSecondary)
                    }
                }
            }
        } header: {
            BondSectionHeader(title: String(localized: "Follow-through · last 7 days"))
        }
        .bondWarmRow()
    }

    private func streakSection(a: LoveLanguageAnalyzer) -> some View {
        let current = a.currentStreak()
        let longest = a.longestStreak()
        // Three stats side by side stop fitting at accessibility sizes, so they stack.
        let large = typeSize.isAccessibilitySize
        let layout = large
            ? AnyLayout(VStackLayout(spacing: BondSpacing.m))
            : AnyLayout(HStackLayout())
        return layout {
            VStack(alignment: .center, spacing: 4) {
                Text("\(current)")
                    .font(.bond(.title, weight: .bold))
                    .foregroundStyle(.pink)
                Text(PluralLabel.dayStreak(current))
                    .font(.bond(.caption))
                    .foregroundStyle(.bondTextSecondary)
            }
            .frame(maxWidth: .infinity)

            if !large { Divider().frame(height: 40) }

            VStack(alignment: .center, spacing: 4) {
                Text("\(longest)")
                    .font(.bond(.title, weight: .bold))
                    .foregroundStyle(.orange)
                Text(PluralLabel.bestStreak(longest))
                    .font(.bond(.caption))
                    .foregroundStyle(.bondTextSecondary)
            }
            .frame(maxWidth: .infinity)

            if !large { Divider().frame(height: 40) }

            VStack(alignment: .center, spacing: 4) {
                Text(a.completionRate().map { (Double(Int($0)) / 100).formatted(.percent) } ?? "–")
                    .font(.bond(.title, weight: .bold))
                    .foregroundStyle(.green)
                Text("done this week")
                    .font(.bond(.caption))
                    .foregroundStyle(.bondTextSecondary)
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
                        .foregroundStyle(.bondTextSecondary)
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
                        .foregroundStyle(.bondTextSecondary)
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
            LabeledContent("Total reminders", value: total.formatted())
            LabeledContent("For partner", value: repo.reminders.filter { $0.authorId != $0.targetId }.count.formatted())
            LabeledContent("Repeating", value: repo.reminders.filter(\.repeatsOnSchedule).count.formatted())
            LabeledContent("Total actions", value: eventsRepo.events.count.formatted())
            LabeledContent("Actions completed", value: eventsRepo.actedCount.formatted())
        }
    }
}
