#if canImport(UIKit)
import UIKit
#endif
import SwiftUI

// Post-sign-in intent capture. Bond is built around showing up for ONE
// specific person, so onboarding centers on them: their name, a commitment
// moment, their love language, and what the user wants to remember for
// them. Everyone starts solo; pairing is opt-in from Settings.

enum FocusArea: String, CaseIterable, Identifiable, Codable {
    case gestures
    case dates
    case loves
    case avoid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gestures: "Little gestures"
        case .dates:    "Important dates"
        case .loves:    "Things they love"
        case .avoid:    "Things to avoid"
        }
    }

    var subtitle: String {
        switch self {
        case .gestures: "Day-to-day ways to show up."
        case .dates:    "Anniversaries, birthdays, plans."
        case .loves:    "Favorites, hobbies, what they care about."
        case .avoid:    "Topics, days, or things that hurt."
        }
    }

    var symbol: String {
        switch self {
        case .gestures: "heart.fill"
        case .dates:    "calendar"
        case .loves:    "sparkles"
        case .avoid:    "exclamationmark.triangle.fill"
        }
    }
}

/// On-device only. The data here describes the *partner* (or whoever the
/// user wants to show up for), captured before pairing exists. If they
/// later pair, the real partner profile becomes the source of truth for
/// shared fields, but these hints remain as the user's private notes.
@MainActor
@Observable
final class OnboardingPreferences {
    static let shared = OnboardingPreferences()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let partnerName = "onboarding.partnerName"
        // Legacy single-language key, kept for one-time migration to the
        // ordered multi-select array.
        static let partnerLoveLanguageLegacy = "onboarding.partnerLoveLanguage"
        static let partnerLoveLanguages = "onboarding.partnerLoveLanguages"
        static let focusAreas = "onboarding.focusAreas"
        static let committedAt = "onboarding.committedAt"
    }

    var partnerName: String {
        didSet { defaults.set(partnerName, forKey: Key.partnerName) }
    }

    /// Ordered list of love languages the user picked for their partner.
    /// First element is the primary — it drives prompt weighting and the
    /// `partnerLoveLanguage` compatibility shim below.
    var partnerLoveLanguages: [LoveLanguage] {
        didSet {
            defaults.set(partnerLoveLanguages.map(\.rawValue), forKey: Key.partnerLoveLanguages)
        }
    }

    /// Compat shim for callers that still want one love language (e.g.
    /// starter-chip suggestions). Reads the primary; assignment promotes the
    /// value to primary in the ordered list.
    var partnerLoveLanguage: LoveLanguage {
        get { partnerLoveLanguages.first ?? .words }
        set { setPrimaryLoveLanguage(newValue) }
    }

    var focusAreas: Set<FocusArea> {
        didSet { defaults.set(focusAreas.map(\.rawValue), forKey: Key.focusAreas) }
    }
    var committedAt: Date? {
        didSet { defaults.set(committedAt, forKey: Key.committedAt) }
    }

    private init() {
        partnerName = defaults.string(forKey: Key.partnerName) ?? ""

        let rawList = defaults.stringArray(forKey: Key.partnerLoveLanguages) ?? []
        let parsed = rawList.compactMap(LoveLanguage.init(rawValue:))
        if !parsed.isEmpty {
            partnerLoveLanguages = parsed
        } else if let legacy = defaults.string(forKey: Key.partnerLoveLanguageLegacy)
            .flatMap(LoveLanguage.init(rawValue:)) {
            partnerLoveLanguages = [legacy]
        } else {
            partnerLoveLanguages = []
        }

        let raw = defaults.stringArray(forKey: Key.focusAreas) ?? []
        focusAreas = Set(raw.compactMap(FocusArea.init(rawValue:)))
        committedAt = defaults.object(forKey: Key.committedAt) as? Date
    }

    func toggleLoveLanguage(_ lang: LoveLanguage) {
        if let idx = partnerLoveLanguages.firstIndex(of: lang) {
            partnerLoveLanguages.remove(at: idx)
        } else {
            partnerLoveLanguages.append(lang)
        }
    }

    func setPrimaryLoveLanguage(_ lang: LoveLanguage) {
        var list = partnerLoveLanguages
        list.removeAll { $0 == lang }
        list.insert(lang, at: 0)
        partnerLoveLanguages = list
    }
}

struct IntentSetupView: View {
    @Environment(PairingService.self) private var pairing
    @State private var prefs = OnboardingPreferences.shared
    @State private var step = 0
    @State private var isFinishing = false
    @FocusState private var nameFocused: Bool

    private var nameTrimmed: String {
        prefs.partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayName: String {
        nameTrimmed.isEmpty ? "them" : nameTrimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BondSpacing.xl) {
            Spacer()

            Group {
                switch step {
                case 0: nameStep
                case 1: commitStep
                case 2: loveLanguageStep
                default: focusAreasStep
                }
            }
            .transition(.opacity)

            if let error = pairing.lastError {
                BondInlineError(message: error)
            }

            Spacer()

            BondPrimaryButton(
                title: continueTitle,
                isLoading: isFinishing
            ) {
                advance()
            }
            .padding(.horizontal, BondSpacing.base)
            .disabled(!canContinue)
        }
        .padding(.vertical, BondSpacing.xxxl)
        .animation(.easeOut(duration: 0.25), value: step)
        // Don't carry a stale error in from a previous failed attempt.
        .onAppear { pairing.lastError = nil }
    }

    private var continueTitle: String {
        switch step {
        case 0, 2: "Continue"
        case 1: "I commit to showing up for \(displayName)"
        default: "Start using Bond"
        }
    }

    private var canContinue: Bool {
        switch step {
        case 0: !nameTrimmed.isEmpty
        case 3: !prefs.focusAreas.isEmpty
        default: true
        }
    }

    private func advance() {
        switch step {
        case 0:
            prefs.partnerName = nameTrimmed
            nameFocused = false
            step = 1
        case 1:
            prefs.committedAt = Date()
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            step = 2
        case 2:
            step = 3
        default:
            Task { await finish() }
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: BondSpacing.xl) {
            BondScreenHeader(
                title: "Who do you want to show up for?",
                subtitle: "Your partner. Bond is built to help you keep showing up for them."
            )
            .padding(.horizontal, BondSpacing.base)

            TextField("Their name", text: $prefs.partnerName)
                .font(.bond(.title3))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(true)
                .submitLabel(.continue)
                .focused($nameFocused)
                .padding(BondSpacing.base)
                .background(Color.bondCardFill, in: RoundedRectangle(cornerRadius: BondRadius.inline))
                .padding(.horizontal, BondSpacing.base)
                .onAppear { nameFocused = true }
                .onSubmit { if canContinue { advance() } }
        }
    }

    private var commitStep: some View {
        VStack(alignment: .leading, spacing: BondSpacing.xl) {
            BondScreenHeader(
                title: "Make it real.",
                subtitle: "Showing up for \(displayName) isn't a feature, it's a choice. Make it now, and Bond will help you keep it."
            )
            .padding(.horizontal, BondSpacing.base)

            HStack {
                Spacer()
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(Color.bondAccent)
                    .accessibilityHidden(true)
                Spacer()
            }
            .padding(.vertical, BondSpacing.l)
        }
    }

    private var loveLanguageStep: some View {
        VStack(alignment: .leading, spacing: BondSpacing.xl) {
            BondScreenHeader(
                title: "What lands best with \(displayName)?",
                subtitle: "Pick any that fit. Your first choice is their primary, we'll lean toward it."
            )
            .padding(.horizontal, BondSpacing.base)

            VStack(spacing: BondSpacing.s) {
                ForEach(LoveLanguage.allCases) { lang in
                    let selected = prefs.partnerLoveLanguages.contains(lang)
                    let isPrimary = prefs.partnerLoveLanguages.first == lang
                    HStack(spacing: BondSpacing.m) {
                        Image(systemName: lang.symbolName)
                            .foregroundStyle(lang.tint)
                            .frame(width: 28)
                        Text(lang.title)
                            .font(.bond(.headline))
                            .foregroundStyle(.primary)
                        if isPrimary {
                            Text("Primary")
                                .font(.bond(.caption2, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.bondAccent.opacity(0.15), in: Capsule())
                                .foregroundStyle(Color.bondAccent)
                                .accessibilityLabel("Primary love language")
                        }
                        Spacer()
                        if selected && !isPrimary {
                            Button("Make primary") {
                                prefs.setPrimaryLoveLanguage(lang)
                            }
                            .font(.bond(.caption, weight: .medium))
                            .buttonStyle(.borderless)
                            .foregroundStyle(Color.bondAccent)
                        }
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.bondAccent)
                        }
                    }
                    .padding(BondSpacing.base)
                    .background(Color.bondCardFill, in: RoundedRectangle(cornerRadius: BondRadius.inline))
                    .contentShape(Rectangle())
                    .onTapGesture { prefs.toggleLoveLanguage(lang) }
                }
            }
            .padding(.horizontal, BondSpacing.base)
        }
    }

    private var focusAreasStep: some View {
        VStack(alignment: .leading, spacing: BondSpacing.xl) {
            BondScreenHeader(
                title: "What do you want to remember about \(displayName)?",
                subtitle: "Pick what matters. You can change any of this later."
            )
            .padding(.horizontal, BondSpacing.base)

            VStack(spacing: BondSpacing.m) {
                ForEach(FocusArea.allCases) { area in
                    BondChoiceCard(
                        symbol: area.symbol,
                        title: area.title,
                        description: area.subtitle,
                        tint: prefs.focusAreas.contains(area) ? .bondAccent : .secondary,
                        trailing: {
                            if prefs.focusAreas.contains(area) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.bondAccent)
                            }
                        },
                        action: {
                            if prefs.focusAreas.contains(area) {
                                prefs.focusAreas.remove(area)
                            } else {
                                prefs.focusAreas.insert(area)
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
        await pairing.createSoloCouple()
    }
}
