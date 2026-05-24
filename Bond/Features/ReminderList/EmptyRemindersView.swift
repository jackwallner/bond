import SwiftUI

struct StarterChip: Identifiable {
    let id = UUID()
    let title: String
    let loveLanguage: LoveLanguage
    var area: FocusArea = .gestures
}

private let starterChipPool: [StarterChip] = [
    // Little gestures
    StarterChip(title: "Tell them they're beautiful", loveLanguage: .words, area: .gestures),
    StarterChip(title: "Ten-minute walk together", loveLanguage: .time, area: .gestures),
    StarterChip(title: "Bring home flowers", loveLanguage: .gifts, area: .gestures),
    StarterChip(title: "A long hug at the door", loveLanguage: .touch, area: .gestures),
    StarterChip(title: "Handle a chore they dread", loveLanguage: .acts, area: .gestures),
    // Important dates
    StarterChip(title: "Note an upcoming date", loveLanguage: .time, area: .dates),
    StarterChip(title: "Plan something for the weekend", loveLanguage: .time, area: .dates),
    // Things they love
    StarterChip(title: "Pick up their favorite snack", loveLanguage: .gifts, area: .loves),
    StarterChip(title: "Play a song they love", loveLanguage: .time, area: .loves),
    StarterChip(title: "Ask about something they care about", loveLanguage: .words, area: .loves),
    // Things to avoid
    StarterChip(title: "Note a topic to steer around", loveLanguage: .words, area: .avoid),
    StarterChip(title: "Phone away during dinner", loveLanguage: .time, area: .avoid)
]

/// Chips tailored to the user's onboarding choices: only their selected
/// focus areas, with the partner's love language floated to the top. Falls
/// back to gestures if they picked nothing (e.g. legacy accounts).
@MainActor
func starterChips(for prefs: OnboardingPreferences) -> [StarterChip] {
    let areas = prefs.focusAreas.isEmpty ? [.gestures] : prefs.focusAreas
    let pool = starterChipPool.filter { areas.contains($0.area) }
    let primary = prefs.partnerLoveLanguage
    let ranked = pool.sorted { ($0.loveLanguage == primary ? 0 : 1) < ($1.loveLanguage == primary ? 0 : 1) }
    return Array(ranked.prefix(5))
}

struct EmptyRemindersView: View {
    let onTapChip: (StarterChip) -> Void
    let onBrowseTemplates: () -> Void

    private var chips: [StarterChip] { starterChips(for: .shared) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: BondSpacing.xxxl)

                VStack(spacing: BondSpacing.m) {
                    Image(systemName: "heart.text.square")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("No reminders yet.")
                        .font(.bond(.title3, weight: .bold))
                    Text("Add one with the + button, or start with these.")
                        .font(.bond(.subheadline))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BondSpacing.xl)
                }

                Spacer().frame(height: BondSpacing.xxl)

                VStack(alignment: .leading, spacing: BondSpacing.m) {
                    Text("Start here")
                        .font(.bond(.subheadline, weight: .bold))
                    ForEach(chips) { chip in
                        Button { onTapChip(chip) } label: {
                            HStack(spacing: BondSpacing.m) {
                                Image(systemName: chip.loveLanguage.symbolName)
                                    .font(.bond(.body))
                                    .foregroundStyle(chip.loveLanguage.tint)
                                    .frame(width: 24)
                                Text(chip.title)
                                    .font(.bond(.callout))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, BondSpacing.base)
                            .padding(.vertical, BondSpacing.m)
                            .background(Color.bondCardFill, in: RoundedRectangle(cornerRadius: BondRadius.inline))
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("Double-tap to start a reminder")
                    }
                }
                .padding(.horizontal, BondSpacing.base)

                Button(action: onBrowseTemplates) {
                    HStack(spacing: BondSpacing.xs) {
                        Text("Browse templates")
                        Image(systemName: "arrow.right")
                    }
                    .font(.bond(.footnote, weight: .bold))
                    .foregroundStyle(Color.bondAccent)
                }
                .padding(.top, BondSpacing.base)

                Spacer()
            }
        }
    }
}

