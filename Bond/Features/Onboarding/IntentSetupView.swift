import SwiftUI

// Post-sign-in intent capture. Replaces the old "Just me / With someone"
// fork: everyone starts solo. We only ask what they want out of Bond so the
// reminders list can seed itself. Pairing is a deliberate opt-in later
// (Settings), since partner setup is heavier lift.

enum ReminderTheme: String, CaseIterable, Identifiable, Codable {
    case selfCare
    case habits
    case partner
    case milestones

    var id: String { rawValue }

    var title: String {
        switch self {
        case .selfCare:   "Self-care"
        case .habits:     "Habits"
        case .partner:    "Someone I love"
        case .milestones: "Dates that matter"
        }
    }

    var subtitle: String {
        switch self {
        case .selfCare:   "Rest, water, a moment to breathe."
        case .habits:     "Small things, done consistently."
        case .partner:    "Little nudges to show up for them."
        case .milestones: "Anniversaries, birthdays, plans."
        }
    }

    var symbol: String {
        switch self {
        case .selfCare:   "leaf.fill"
        case .habits:     "repeat"
        case .partner:    "heart.fill"
        case .milestones: "calendar"
        }
    }
}

/// On-device only. Per product decision, preferences stay local until the
/// user actually pairs with a partner — at which point love language is
/// pushed to their server profile (see PairingService).
@MainActor
@Observable
final class OnboardingPreferences {
    static let shared = OnboardingPreferences()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let loveLanguage = "onboarding.loveLanguage"
        static let themes = "onboarding.themes"
    }

    var primaryLoveLanguage: LoveLanguage {
        didSet { defaults.set(primaryLoveLanguage.rawValue, forKey: Key.loveLanguage) }
    }
    var themes: Set<ReminderTheme> {
        didSet {
            defaults.set(themes.map(\.rawValue), forKey: Key.themes)
        }
    }

    private init() {
        primaryLoveLanguage = (defaults.string(forKey: Key.loveLanguage))
            .flatMap(LoveLanguage.init(rawValue:)) ?? .words
        let raw = defaults.stringArray(forKey: Key.themes) ?? []
        themes = Set(raw.compactMap(ReminderTheme.init(rawValue:)))
    }
}

struct IntentSetupView: View {
    @Environment(PairingService.self) private var pairing
    @State private var prefs = OnboardingPreferences.shared
    @State private var step = 0
    @State private var isFinishing = false

    var body: some View {
        VStack(alignment: .leading, spacing: BondSpacing.xl) {
            Spacer()

            if step == 0 {
                loveLanguageStep
            } else {
                themesStep
            }

            if let error = pairing.lastError {
                BondInlineError(message: error)
            }

            Spacer()

            BondPrimaryButton(
                title: step == 0 ? "Continue" : "Start using Bond",
                isLoading: isFinishing
            ) {
                if step == 0 {
                    withAnimation { step = 1 }
                } else {
                    Task { await finish() }
                }
            }
            .padding(.horizontal, BondSpacing.base)
            .disabled(step == 1 && prefs.themes.isEmpty)
        }
        .padding(.vertical, BondSpacing.xxxl)
    }

    private var loveLanguageStep: some View {
        VStack(alignment: .leading, spacing: BondSpacing.xl) {
            BondScreenHeader(
                title: "What lands best with you?",
                subtitle: "Your primary love language. We'll lean prompts and suggestions toward it."
            )
            .padding(.horizontal, BondSpacing.base)

            VStack(spacing: BondSpacing.s) {
                ForEach(LoveLanguage.allCases) { lang in
                    Button {
                        prefs.primaryLoveLanguage = lang
                    } label: {
                        HStack(spacing: BondSpacing.m) {
                            Image(systemName: lang.symbolName)
                                .foregroundStyle(lang.tint)
                                .frame(width: 28)
                            Text(lang.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Spacer()
                            if prefs.primaryLoveLanguage == lang {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.bondAccent)
                            }
                        }
                        .padding(BondSpacing.base)
                        .background(Color.bondCardFill, in: RoundedRectangle(cornerRadius: BondRadius.inline))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, BondSpacing.base)
        }
    }

    private var themesStep: some View {
        VStack(alignment: .leading, spacing: BondSpacing.xl) {
            BondScreenHeader(
                title: "What do you want nudges about?",
                subtitle: "Pick what fits. You can change any of this later."
            )
            .padding(.horizontal, BondSpacing.base)

            VStack(spacing: BondSpacing.m) {
                ForEach(ReminderTheme.allCases) { theme in
                    BondChoiceCard(
                        symbol: theme.symbol,
                        title: theme.title,
                        description: theme.subtitle,
                        tint: prefs.themes.contains(theme) ? .bondAccent : .secondary,
                        trailing: {
                            if prefs.themes.contains(theme) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.bondAccent)
                            }
                        },
                        action: {
                            if prefs.themes.contains(theme) {
                                prefs.themes.remove(theme)
                            } else {
                                prefs.themes.insert(theme)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, BondSpacing.base)
        }
    }

    private func finish() async {
        isFinishing = true
        defer { isFinishing = false }
        // Saving prefs is a side effect of the @Observable setters; creating
        // the solo couple flips the router to home.
        await pairing.createSoloCouple()
    }
}
