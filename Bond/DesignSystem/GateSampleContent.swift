import Charts
import SwiftUI

// Faithful, static, synthetic renders of each premium feature for the gate
// preview. Never calls live services; every label is prefixed "Sample ·"
// so it can't be mistaken for real data, even in a screen recording.

struct InsightsGateContent: View {
    private let dist: [(LoveLanguage, Int)] = [
        (.words, 38), (.acts, 12), (.gifts, 8), (.time, 28), (.touch, 14)
    ]

    var body: some View {
        Form {
            Section {
                HStack {
                    metric(12, PluralLabel.dayStreak(12), .pink)
                    Divider().frame(height: 40)
                    metric(31, PluralLabel.bestStreak(31), .orange)
                    Divider().frame(height: 40)
                    metric(64, String(localized: "balance"), .green)
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
                    .font(.bond(.subheadline))
            }
        }
    }

    private func metric(_ value: Int, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: BondSpacing.xs) {
            Text(value.formatted()).font(.bond(.title, weight: .bold)).foregroundStyle(tint)
            Text(label).font(.bond(.caption)).foregroundStyle(.bondTextSecondary)
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
                        .font(.bond(.title))
                        .foregroundStyle(LoveLanguage.words.tint)
                    Text("Sample · What is one thing you appreciated about your partner today?")
                        .font(.bond(.title3))
                        .multilineTextAlignment(.center)
                    Text(LoveLanguage.words.title)
                        .font(.bond(.caption))
                        .foregroundStyle(LoveLanguage.words.tint)
                        .padding(.horizontal, BondSpacing.m)
                        .padding(.vertical, BondSpacing.xs)
                        .background(LoveLanguage.words.tint.opacity(0.12), in: Capsule())
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.bondCardFill, in: RoundedRectangle(cornerRadius: BondRadius.card))

                BondSealedCard(title: String(localized: "Sample · Sarah answered"),
                               hint: String(localized: "Sealed until you both reply"))
            }
            .padding()
        }
    }
}

struct TemplatesGateContent: View {
    private var groups: [(String, String, String)] {
        [
            ("quote.bubble.fill", String(localized: "Sample · Daily Affirmations"), String(localized: "\(7) reminders")),
            ("sparkles", String(localized: "Sample · Date Night"), String(localized: "\(5) reminders")),
            ("airplane", String(localized: "Sample · Long Distance"), String(localized: "\(6) reminders"))
        ]
    }

    var body: some View {
        List {
            ForEach(groups, id: \.1) { icon, title, count in
                HStack(spacing: BondSpacing.m) {
                    Image(systemName: icon).font(.bond(.title2)).foregroundStyle(.pink).frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.bond(.headline))
                        Text(count).font(.bond(.caption)).foregroundStyle(.bondTextSecondary)
                    }
                    Spacer()
                }
                .padding(.vertical, BondSpacing.xs)
            }
        }
    }
}
