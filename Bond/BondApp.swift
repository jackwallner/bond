import StoreKit
import SwiftUI
import UIKit

@main
struct BondApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var supabase = SupabaseService.shared
    @State private var store = PurchasesService.shared
    @State private var pairingService: PairingService
    @State private var reminderRepo: ReminderRepository
    @State private var milestonesService: MilestonesService
    @State private var eventsRepo: ReminderEventRepository
    @State private var checkInService: DailyCheckInService

    init() {
        let pairing = PairingService()
        let repo = ReminderRepository(pairing: pairing)
        let milestones = MilestonesService(pairing: pairing)
        let events = ReminderEventRepository(pairing: pairing)
        let checkIn = DailyCheckInService(pairing: pairing)

        _pairingService = State(initialValue: pairing)
        _reminderRepo = State(initialValue: repo)
        _milestonesService = State(initialValue: milestones)
        _eventsRepo = State(initialValue: events)
        _checkInService = State(initialValue: checkIn)

        Self.applyNavigationBarFont()
        ReviewPromptTracker.recordAppLaunch()
    }

    /// Nav-bar titles are rendered by UIKit, so SwiftUI's `.font(.bond(...))`
    /// default doesn't reach them. Point the title + large-title text attributes
    /// at the bundled brand face so navigation chrome matches in-content type.
    private static func applyNavigationBarFont() {
        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        // At rest the bar must show the warm wash, not an opaque system
        // material — a gray-white slab at the top of every screen is the one
        // place the unified warm surface still broke in light mode. The blur
        // returns only once content scrolls under the bar.
        let scrollEdge = UINavigationBarAppearance()
        scrollEdge.configureWithTransparentBackground()
        for appearance in [standard, scrollEdge] {
            if let title = UIFont(name: "PlusJakartaSans-Bold", size: 17) {
                appearance.titleTextAttributes[.font] = title
            }
            if let large = UIFont(name: "PlusJakartaSans-Bold", size: 34) {
                appearance.largeTitleTextAttributes[.font] = large
            }
        }
        UINavigationBar.appearance().standardAppearance = standard
        UINavigationBar.appearance().scrollEdgeAppearance = scrollEdge
        UINavigationBar.appearance().compactAppearance = standard
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(supabase)
                .environment(store)
                .environment(pairingService)
                .environment(reminderRepo)
                .environment(milestonesService)
                .environment(eventsRepo)
                .environment(checkInService)
                .onAppear {
                    NotificationRouter.shared.install()
                    WatchConnectivityBridge.shared.start(
                        repository: reminderRepo,
                        supabase: supabase,
                        pairing: pairingService
                    )
                    reminderRepo.onChange = { reminders in
                        WidgetSnapshotPump.push(
                            reminders: reminders,
                            milestones: milestonesService.milestones
                        )
                    }
                    Task { await store.bootstrap() }
                }
                .onOpenURL { url in
                    pairingService.handleIncomingURL(url)
                }
                .onChange(of: scenePhase) { _, phase in
                    // Re-pull entitlements when returning to foreground.
                    // App Store transactions can take a moment to propagate
                    // to RevenueCat — without this, a paid user can sit on a
                    // stale isPremium=false until they reopen the app.
                    if phase == .active {
                        Task { await store.refresh() }
                        // A solo user may have been paired while backgrounded
                        // (their partner consumed the invite). Refresh so the
                        // app notices without a relaunch.
                        if pairingService.solo {
                            Task { await pairingService.loadCouple() }
                        }
                    }
                }
        }
    }
}

struct RootView: View {
    @Environment(SupabaseService.self) private var supabase
    @Environment(PurchasesService.self) private var store
    @Environment(PairingService.self) private var pairing
    @StateObject private var reviewPromptCoordinator = ReviewPromptCoordinator.shared
    @State private var theme = BondTheme.shared
    @State private var onboardingPrefs = OnboardingPreferences.shared
    // Stays false until both auth bootstrap AND the initial couple load have
    // settled. Without this single gate, the destination resolved off
    // mid-flight state and flashed intent-setup → loading → home on launch.
    @State private var isAppBootstrapped = false
    @State private var showReviewPrompt = false
    @State private var showPostPairPaywall = false
    private let postPairPaywallKey = "hasShownPostPairPaywall"
    @State private var reviewPromptInitialStep: ReviewPromptSheet.Step = .enjoyment
    @State private var reviewPromptShownThisSession = false
    @State private var pendingNativeReviewAfterDismiss = false
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        // Touch theme.accent so the body re-evaluates when the user picks a
        // new palette; subviews reading Color.bondAccent then get the new
        // value via normal SwiftUI prop diffing (no view-identity reset).
        _ = theme.accent
        return Group {
            switch currentDestination {
            case .intentSetup:
                IntentSetupView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            case .inviteWelcome:
                InviteWelcomeView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            case .inviteeIntake:
                IntentSetupView(mode: .invitee)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            case .pairingSuccess:
                PairingSuccessView(partnerName: pairing.partnerProfile?.displayName) {
                    // Pairing is a high-intent moment and the headline Bond+
                    // benefit (Daily Check-In) just became usable. Offer the
                    // paywall once, dismissibly, before dropping the now-paired
                    // user onto home. Premium users (and anyone who's already
                    // seen it) skip straight through.
                    if !store.isPremium && !UserDefaults.standard.bool(forKey: postPairPaywallKey) {
                        UserDefaults.standard.set(true, forKey: postPairPaywallKey)
                        showPostPairPaywall = true
                    } else {
                        pairing.justPaired = false
                    }
                }
                .transition(.opacity)
            case .home:
                MainTabView()
                    .transition(.opacity)
            case .loading:
                ZStack {
                    Color.bondSurface.ignoresSafeArea()
                    if isAppBootstrapped && !supabase.isAuthenticated {
                        // Bootstrap finished but no session exists — almost
                        // always a first-launch network failure (anonymous
                        // sign-in needs the network). Offer a way forward
                        // instead of an indefinite spinner.
                        loadingFailedState
                    } else {
                        ProgressView()
                            .controlSize(.large)
                    }
                }
                .transition(.opacity)
            }
        }
        // Soft Tactile visual system, applied app-wide:
        // • Plus Jakarta Sans (bundled) is the brand face; `.font(.bond(.body))`
        //   sets the default so any Text without an explicit style inherits it
        // • warm cream→peach wash behind all content
        // • accent tint flows to every system control (links, switches, etc.)
        .background(Color.bondBackgroundGradient.ignoresSafeArea())
        .font(.bond(.body))
        .tint(.bondAccent)
        // Honor the Settings light/dark/system override; reading
        // theme.appearance here registers the dependency so picking a new
        // mode re-evaluates the body and flips every Color(light:dark:).
        .preferredColorScheme(theme.appearance.colorScheme)
        .animation(.easeOut(duration: 0.35), value: currentDestination)
        .sheet(isPresented: Binding(
            // Only for users who already finished setup (a couple exists).
            // Pre-setup, the same state routes to the full-screen
            // InviteWelcomeView instead — presenting both stacked a Settings
            // -style sheet on top of the invitee's own onboarding.
            get: { pairing.requiresSignInToPair && pairing.coupleId != nil },
            set: { if !$0 { pairing.requiresSignInToPair = false } }
        )) {
            // Universal-link arrived for an anonymous user. Surface the gate
            // directly so they don't have to navigate Settings → Pair to
            // discover that their tap "did" something.
            NavigationStack {
                AppleSignInPairingGate()
                    .navigationTitle("Pair")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Not now") {
                                pairing.deferredInviteCode = nil
                                pairing.requiresSignInToPair = false
                            }
                        }
                    }
            }
        }
        .task {
            // Single, idempotent session bootstrap. Restores a cached session
            // or silently signs in anonymously on first launch. Must be the
            // only entry point — calling signInAnonymously() in parallel with
            // init's restoreSession() can mint two anon users and leave the
            // client session out of sync with currentUserId.
            await supabase.bootstrap()
            if let me = supabase.currentUserId {
                await store.identify(supabaseUserId: me)
            }
            await pairing.loadCouple()
            isAppBootstrapped = true
        }
        .onChange(of: supabase.isAuthenticated) { _, authenticated in
            guard authenticated, isAppBootstrapped else { return }
            isAppBootstrapped = false
            Task {
                await pairing.loadCouple()
                isAppBootstrapped = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bondPositiveMomentForReview)) { _ in
            scheduleReviewPromptAfterPositiveMoment()
        }
        .onChange(of: reviewPromptCoordinator.pendingPresentation) { _, presentation in
            guard let presentation else { return }
            defer { reviewPromptCoordinator.clear() }
            guard currentDestination == .home,
                  !pairing.requiresSignInToPair
            else { return }
            switch presentation {
            case .enjoymentPrompt:
                presentReviewPrompt(step: .enjoyment)
            case .feedbackOnly:
                presentReviewPrompt(step: .feedback)
            }
        }
        .sheet(isPresented: $showReviewPrompt, onDismiss: {
            if pendingNativeReviewAfterDismiss {
                pendingNativeReviewAfterDismiss = false
                requestReview()
            }
        }) {
            ReviewPromptSheet(initialStep: reviewPromptInitialStep, onFinish: handleReviewPromptFinish)
        }
        // Proactive post-pairing paywall. Whether the user buys or closes it,
        // dismissal advances past the success screen to home.
        .sheet(isPresented: $showPostPairPaywall, onDismiss: { pairing.justPaired = false }) {
            PaywallView(onClose: { showPostPairPaywall = false }, impressionId: "post_pairing")
                .presentationDragIndicator(.visible)
        }
    }

    private var hasCompletedSetup: Bool {
        isAppBootstrapped && pairing.coupleId != nil
    }

    private var loadingFailedState: some View {
        VStack(spacing: BondSpacing.m) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Couldn't connect")
                .font(.bond(.headline))
            Text("Bond needs a connection the first time you open it. Check your network and try again.")
                .font(.bond(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BondSpacing.xl)
            Button("Try again") { retryBootstrap() }
                .font(.bond(.subheadline, weight: .semibold))
                .foregroundStyle(Color.bondAccent)
        }
    }

    private func retryBootstrap() {
        Task {
            isAppBootstrapped = false
            await supabase.retryBootstrap()
            if let me = supabase.currentUserId {
                await store.identify(supabaseUserId: me)
            }
            await pairing.loadCouple()
            isAppBootstrapped = true
        }
    }

    private func scheduleReviewPromptAfterPositiveMoment() {
        guard currentDestination == .home,
              !pairing.justPaired,
              !pairing.requiresSignInToPair,
              ReviewPromptTracker.shouldShowAfterPositiveMoment(hasCompletedSetup: hasCompletedSetup),
              !reviewPromptShownThisSession,
              !showReviewPrompt
        else { return }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard currentDestination == .home,
                  !pairing.justPaired,
                  !pairing.requiresSignInToPair,
                  !showReviewPrompt,
                  ReviewPromptTracker.shouldShowAfterPositiveMoment(hasCompletedSetup: hasCompletedSetup)
            else { return }
            ReviewPromptTracker.consumePendingPositiveMoment()
            reviewPromptInitialStep = .enjoyment
            reviewPromptShownThisSession = true
            showReviewPrompt = true
        }
    }

    private func handleReviewPromptFinish(_ outcome: ReviewPromptDismissOutcome) {
        showReviewPrompt = false
        if outcome == .enjoyedMaybeLater {
            pendingNativeReviewAfterDismiss = true
        }
    }

    private func presentReviewPrompt(step: ReviewPromptSheet.Step) {
        reviewPromptInitialStep = step
        reviewPromptShownThisSession = true
        showReviewPrompt = true
    }

    private enum Destination { case loading, intentSetup, inviteWelcome, inviteeIntake, pairingSuccess, home }

    private var currentDestination: Destination {
        if !isAppBootstrapped || !supabase.isAuthenticated {
            return .loading
        }
        // No couple at all = brand-new account. Someone arriving from a
        // partner's invite link gets invite-first onboarding; everyone else
        // starts solo via the intent screen, and pairing stays opt-in from
        // Settings.
        if pairing.coupleId == nil {
            return pairing.deferredInviteCode != nil ? .inviteWelcome : .intentSetup
        }
        if pairing.justPaired {
            return .pairingSuccess
        }
        // Paired, but this device never captured onboarding preferences —
        // the invitee path skips intent setup entirely. Run the trimmed
        // intake (love language + focus areas) once before home.
        if !pairing.solo, onboardingPrefs.committedAt == nil, onboardingPrefs.focusAreas.isEmpty {
            return .inviteeIntake
        }
        return .home
    }
}

/// Primary navigation. Each core area is a tab so nothing is buried — the
/// previous design hid Check-In, Milestones, Insights, and Settings behind a
/// single top-left "..." that read as overflow, and most users never found
/// them. Each tab root owns its own NavigationStack (Settings doesn't, so it's
/// wrapped here).
struct MainTabView: View {
    @State private var router = NotificationRouter.shared
    @State private var selection: Tab = .reminders

    private enum Tab: Hashable { case reminders, checkIn, milestones, insights, settings }

    var body: some View {
        TabView(selection: $selection) {
            ReminderListView()
                .tag(Tab.reminders)
                .tabItem { Label("Reminders", systemImage: "bell.fill") }

            DailyCheckInView()
                .tag(Tab.checkIn)
                .tabItem { Label("Check-In", systemImage: "questionmark.bubble.fill") }

            MilestonesView()
                .tag(Tab.milestones)
                .tabItem { Label("Milestones", systemImage: "calendar") }

            StatsView()
                .tag(Tab.insights)
                .tabItem { Label("Insights", systemImage: "chart.bar.fill") }

            NavigationStack { SettingsView() }
                .tag(Tab.settings)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        // A tapped reminder notification should land on the Reminders tab, where
        // ReminderListView presents the editor — otherwise the editor sheet would
        // pop up over whatever tab the user happened to be on.
        .onChange(of: router.pendingReminderId) { _, id in
            if id != nil { selection = .reminders }
        }
        .onAppear {
            if router.pendingReminderId != nil { selection = .reminders }
        }
    }
}
