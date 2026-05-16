import SwiftUI

struct StarterChip: Identifiable {
    let id = UUID()
    let title: String
    let loveLanguage: LoveLanguage
    var theme: ReminderTheme = .partner
}

private let starterChipPool: [StarterChip] = [
    // Partner
    StarterChip(title: "Tell them they're beautiful", loveLanguage: .words, theme: .partner),
    StarterChip(title: "Ten-minute walk together", loveLanguage: .time, theme: .partner),
    StarterChip(title: "Bring home flowers", loveLanguage: .gifts, theme: .partner),
    StarterChip(title: "A long hug at the door", loveLanguage: .touch, theme: .partner),
    StarterChip(title: "Handle a chore they dread", loveLanguage: .acts, theme: .partner),
    // Self-care
    StarterChip(title: "Drink a full glass of water", loveLanguage: .acts, theme: .selfCare),
    StarterChip(title: "Five quiet minutes, no phone", loveLanguage: .time, theme: .selfCare),
    StarterChip(title: "Step outside for fresh air", loveLanguage: .time, theme: .selfCare),
    // Habits
    StarterChip(title: "Stretch for two minutes", loveLanguage: .acts, theme: .habits),
    StarterChip(title: "Write one line in a journal", loveLanguage: .words, theme: .habits),
    StarterChip(title: "Tidy one surface", loveLanguage: .acts, theme: .habits),
    // Milestones
    StarterChip(title: "Note an upcoming date", loveLanguage: .time, theme: .milestones),
    StarterChip(title: "Plan something for the weekend", loveLanguage: .time, theme: .milestones)
]

/// Chips tailored to the user's onboarding choices: only their selected
/// themes, with their primary love language floated to the top. Falls back
/// to the partner set if they picked nothing (e.g. legacy accounts).
@MainActor
func starterChips(for prefs: OnboardingPreferences) -> [StarterChip] {
    let themes = prefs.themes.isEmpty ? [.partner] : prefs.themes
    let pool = starterChipPool.filter { themes.contains($0.theme) }
    let primary = prefs.primaryLoveLanguage
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
                        .font(.title3.bold())
                    Text("Add one with the + button, or start with these.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BondSpacing.xl)
                }

                Spacer().frame(height: BondSpacing.xxl)

                VStack(alignment: .leading, spacing: BondSpacing.m) {
                    Text("Start here")
                        .font(.subheadline.bold())
                    ForEach(chips) { chip in
                        Button { onTapChip(chip) } label: {
                            HStack(spacing: BondSpacing.m) {
                                Image(systemName: chip.loveLanguage.symbolName)
                                    .font(.body)
                                    .foregroundStyle(chip.loveLanguage.tint)
                                    .frame(width: 24)
                                Text(chip.title)
                                    .font(.callout)
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
                    .font(.footnote.bold())
                    .foregroundStyle(Color.bondAccent)
                }
                .padding(.top, BondSpacing.base)

                Spacer()
            }
        }
    }
}

struct FilteredEmptyView: View {
    let onShowAll: () -> Void

    var body: some View {
        VStack(spacing: BondSpacing.base) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Nothing for you right now.")
                .font(.headline)
            Text("Your partner is the lucky one today.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Show all reminders", action: onShowAll)
                .buttonStyle(.bordered)
                .tint(.bondAccent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BondSpacing.xxl)
        .listRowBackground(Color.clear)
    }
}
