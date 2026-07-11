#if canImport(UIKit)
import UIKit
#endif
import RevenueCat
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
    /// First element is the primary - it drives prompt weighting and the
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
    /// `.solo` is the full first-run flow (name → commit → love language →
    /// focus areas) ending in solo-couple creation. `.invitee` is the
    /// trimmed intake shown right after pairing via an invite: the partner
    /// is already known (name comes from their profile), so it starts at
    /// the love-language step and finishes without touching the server.
    enum Mode { case solo, invitee }

    @Environment(PairingService.self) private var pairing
    @Environment(PurchasesService.self) private var store
    @State private var prefs = OnboardingPreferences.shared
    @State private var step: Int
    @State private var isFinishing = false
    @State private var showInvitePairing = false
    @State private var isPurchasing = false
    @State private var purchaseError: String?
    @State private var showFallbackPaywall = false
    @FocusState private var nameFocused: Bool

    private let mode: Mode

    /// Total steps for the solo flow. The invitee flow (partner already known)
    /// stops after focus areas and never reaches the trial step.
    private static let trialStep = 4

    init(mode: Mode = .solo) {
        self.mode = mode
        _step = State(initialValue: mode == .invitee ? 2 : 0)
    }

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
                case 3: focusAreasStep
                default: OnboardingTrialView(displayName: displayName)
                }
            }
            .transition(.opacity)

            if let error = pairing.lastError {
                BondInlineError(message: error)
            }

            Spacer()

            ctaRegion
        }
        .padding(.vertical, BondSpacing.xxxl)
        .animation(.easeOut(duration: 0.25), value: step)
        // Don't carry a stale error in from a previous failed attempt.
        .onAppear {
            pairing.lastError = nil
            // Warm the offerings so the trial step has live price/trial copy
            // the instant the user arrives (bootstrap usually beat us here,
            // but a cold/slow launch might not have).
            if store.products.isEmpty {
                Task { await store.fetchProducts() }
            }
        }
        // "Have an invite code?" - a fresh install whose partner already uses
        // Bond shouldn't have to finish solo setup just to reach Settings →
        // Connect a partner. Pairing here flips RootView straight to the
        // success screen, abandoning the rest of this flow.
        .sheet(isPresented: $showInvitePairing) {
            PairingView(initialMode: .receive)
        }
        // Emergency fallback only: offerings never loaded, so we can't
        // direct-purchase. Hand off to the full paywall; whatever the user
        // does there, dismissal proceeds into the app.
        .sheet(isPresented: $showFallbackPaywall, onDismiss: { Task { await finish() } }) {
            PaywallFlowSheet(
                impressionId: "onboarding_trial_fallback",
                onClose: { showFallbackPaywall = false }
            )
        }
    }

    private var isTrialStep: Bool { step == Self.trialStep }

    /// Bottom CTA stack. The primary button is bottom-pinned with a fixed-height
    /// legal-footer slot beneath it on *every* step (empty on non-trial steps),
    /// so its frame is identical across the whole flow. On the trial step the
    /// soft "Get Started" exit and the price disclosure stack *above* the
    /// primary and grow upward - they never push the primary button down.
    @ViewBuilder
    private var ctaRegion: some View {
        VStack(spacing: BondSpacing.s) {
            if isTrialStep {
                Button { Task { await finish() } } label: {
                    Text("Get Started")
                        .font(.bond(.headline))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.bondCardFill, in: RoundedRectangle(cornerRadius: BondRadius.inline, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: BondRadius.inline, style: .continuous)
                                .strokeBorder(Color.bondHairline, lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isPurchasing || isFinishing)

                if let disclosure = trialDisclosure {
                    Text(disclosure)
                        .font(.bond(.caption2))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let purchaseError {
                    Text(purchaseError)
                        .font(.bond(.caption2))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            BondPrimaryButton(
                title: continueTitle,
                isLoading: isFinishing || isPurchasing
            ) {
                advance()
            }
            .disabled(!canContinue)

            legalFooterSlot
        }
        .padding(.horizontal, BondSpacing.base)
    }

    /// Fixed-height footer reserved on all steps so the primary CTA sits at the
    /// same y on every page. Trial step fills it with Restore + Terms/Privacy.
    @ViewBuilder
    private var legalFooterSlot: some View {
        Group {
            if isTrialStep {
                VStack(spacing: BondSpacing.xs) {
                    Button {
                        Task {
                            await store.restore()
                            if store.isPremium { await finish() }
                        }
                    } label: {
                        Text("Restore Purchases")
                            .font(.bond(.caption, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isPurchasing || isFinishing)

                    HStack(spacing: BondSpacing.xs) {
                        Link("Terms", destination: PaywallLinks.terms)
                        Text("·").foregroundStyle(.tertiary)
                        Link("Privacy", destination: PaywallLinks.privacyPolicy)
                    }
                    .font(.bond(.caption2))
                    .foregroundStyle(.tertiary)
                }
            } else {
                Color.clear
            }
        }
        .frame(height: 44)
    }

    private var continueTitle: String {
        switch step {
        case 0, 2: "Continue"
        case 1: "I commit to showing up for \(displayName)"
        case 3: "Start using Bond"
        default: trialCTATitle
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
        case 3:
            // The invitee flow finishes here (partner already known, no solo
            // couple to create). The solo flow gets the trial step next.
            if mode == .invitee {
                Task { await finish() }
            } else {
                enterTrialStep()
            }
        default:
            startTrialPurchase()
        }
    }

    /// Advance to the trial step and pre-empt the post-home paywall. RootView
    /// fires a `PaywallFlowSheet` after the notification primer resolves on the
    /// solo home arrival; once the user has seen this in-flow trial page, that
    /// sheet must not double-fire. Setting the flag here (before couple
    /// creation) makes RootView's guard skip it whether the user buys or exits.
    private func enterTrialStep() {
        UserDefaults.standard.set(true, forKey: "hasShownPostOnboardingPaywall")
        purchaseError = nil
        step = Self.trialStep
    }

    // MARK: - Trial step

    private var trialPackage: Package? {
        store.products.first { $0.bondPackageKind == .yearly } ?? store.products.first
    }

    private var introEligible: Bool {
        guard let package = trialPackage else { return false }
        return store.isEligibleForIntroOffer(package)
    }

    /// Primary CTA label - live RC trial copy when the user is intro-eligible,
    /// otherwise a plain upgrade label (never promise a trial StoreKit won't
    /// honor for a previously-subscribed Apple ID).
    private var trialCTATitle: String {
        if introEligible, let days = trialPackage?.bondTrialDays {
            return "Start \(days)-Day Free Trial"
        }
        return "Get Bond+"
    }

    private var trialDisclosure: String? {
        guard let price = trialPackage?.bondPriceLabel else { return nil }
        if introEligible, let days = trialPackage?.bondTrialDays {
            let phrase = days == 1 ? "1 day" : "\(days) days"
            return "Free for \(phrase), then \(price). Auto-renews unless cancelled 24h before trial ends."
        }
        return "\(price). Auto-renews unless cancelled."
    }

    /// One-tap conversion: buy the yearly package in place (trial when eligible,
    /// straight purchase otherwise) - Apple's confirm sheet, no plan picker.
    /// The full paywall is only the fallback when offerings never loaded.
    private func startTrialPurchase() {
        guard let package = trialPackage else {
            showFallbackPaywall = true
            return
        }
        purchaseError = nil
        isPurchasing = true
        Task { @MainActor in
            defer { isPurchasing = false }
            do {
                switch try await store.purchase(package) {
                case .purchased, .pending:
                    await finish()
                case .cancelled:
                    break
                }
            } catch {
                purchaseError = store.lastError ?? "Couldn't complete the purchase. Please try again."
            }
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

            Button {
                nameFocused = false
                showInvitePairing = true
            } label: {
                Label("Have an invite from your partner?", systemImage: "envelope.open.fill")
                    .font(.bond(.subheadline, weight: .medium))
            }
            .foregroundStyle(Color.bondAccent)
            .padding(.horizontal, BondSpacing.base)
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
        switch mode {
        case .solo:
            isFinishing = true
            defer { isFinishing = false }
            await pairing.createSoloCouple()
        case .invitee:
            // Already paired - the couple exists. Stamping committedAt marks
            // the intake complete, which is what flips RootView to home.
            prefs.committedAt = Date()
        }
    }
}
