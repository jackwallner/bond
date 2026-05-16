import Charts
import SwiftUI

// Faithful, static, synthetic renders of each premium feature for the gate
// preview. Never calls live services; every label is prefixed "Sample ·"
// so it can't be mistaken for real data, even in a screen recording.

struct MilestonesGateContent: View {
    private let rows: [(String, String, String)] = [
        ("heart.fill", "Sample · Our anniversary", "in 87 days"),
        ("gift.fill", "Sample · Sarah's birthday", "in 142 days"),
        ("heart.fill", "Sample · The day we moved in", "in 6 months")
    ]

    var body: some View {
        List {
            ForEach(rows, id: \.1) { icon, label, when in
                HStack(spacing: BondSpacing.m) {
                    Image(systemName: icon).foregroundStyle(.pink).frame(width: 28)
                    Text(label).font(.headline)
                    Spacer()
                    Text(when).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct InsightsGateContent: View {
    private let dist: [(LoveLanguage, Int)] = [
        (.words, 38), (.acts, 12), (.gifts, 8), (.time, 28), (.touch, 14)
    ]

    var body: some View {
        Form {
            Section {
                HStack {
                    metric("12", "day streak", .pink)
                    Divider().frame(height: 40)
                    metric("31", "best streak", .orange)
                    Divider().frame(height: 40)
                    metric("64", "balance", .green)
                }
            }
            Section("Sample · Love Language Distribution") {
                Chart(dist, id: \.0) { item in
                    BarMark(x: .value("Count", item.1), y: .value("Language", item.0.title))
                        .foregroundStyle(item.0.tint)
                }
                .frame(height: 200)
            }
            Section("Sample · What we noticed") {
                Label("Sample · Quality Time is your least-expressed love language this month.",
                      systemImage: "lightbulb.fill")
                    .font(.subheadline)
            }
        }
    }

    private func metric(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: BondSpacing.xs) {
            Text(value).font(.title.bold()).foregroundStyle(tint)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct CheckInGateContent: View {
    var body: some View {
        ScrollView {
            VStack(spacing: BondSpacing.xl) {
                VStack(spacing: BondSpacing.m) {
                    Image(systemName: LoveLanguage.words.symbolName)
                        .font(.title)
                        .foregroundStyle(LoveLanguage.words.tint)
                    Text("Sample · What is one thing you appreciated about your partner today?")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                    Text(LoveLanguage.words.title)
                        .font(.caption)
                        .foregroundStyle(LoveLanguage.words.tint)
                        .padding(.horizontal, BondSpacing.m)
                        .padding(.vertical, BondSpacing.xs)
                        .background(LoveLanguage.words.tint.opacity(0.12), in: Capsule())
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.bondCardFill, in: RoundedRectangle(cornerRadius: BondRadius.card))

                BondSealedCard(title: "Sample · Sarah answered",
                               hint: "Sealed until you both reply")
            }
            .padding()
        }
    }
}

struct TemplatesGateContent: View {
    private let groups: [(String, String, String)] = [
        ("quote.bubble.fill", "Sample · Daily Affirmations", "7 reminders"),
        ("sparkles", "Sample · Date Night", "5 reminders"),
        ("airplane", "Sample · Long Distance", "6 reminders")
    ]

    var body: some View {
        List {
            ForEach(groups, id: \.1) { icon, title, count in
                HStack(spacing: BondSpacing.m) {
                    Image(systemName: icon).font(.title2).foregroundStyle(.pink).frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.headline)
                        Text(count).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, BondSpacing.xs)
            }
        }
    }
}
