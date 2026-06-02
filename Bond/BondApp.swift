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
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        if let title = UIFont(name: "PlusJakartaSans-Bold", size: 17) {
            appearance.titleTextAttributes[.font] = title
        }
        if let large = UIFont(name: "PlusJakartaSans-Bold", size: 34) {
            appearance.largeTitleTextAttributes[.font] = large
        }
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
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
                ReminderListView()
                    .transition(.opacity)
            case .loading:
                ZStack {
                    Color.bondSurface.ignoresSafeArea()
                    ProgressView()
                        .controlSize(.large)
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
        .animation(.easeOut(duration: 0.35), value: currentDestination)
        .sheet(isPresented: Binding(
            get: { pairing.requiresSignInToPair },
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

    private enum Destination { case loading, intentSetup, pairingSuccess, home }

    private var currentDestination: Destination {
        if !isAppBootstrapped || !supabase.isAuthenticated {
            return .loading
        }
        // No couple at all = brand-new account. Everyone starts solo; the
        // intent screen captures preferences and creates the solo couple.
        // Pairing is opt-in from Settings, not a setup gate.
        if pairing.coupleId == nil {
            return .intentSetup
        }
        if pairing.justPaired {
            return .pairingSuccess
        }
        return .home
    }
}

struct BondMoreView: View {
    var body: some View {
        List {
            Section("Relationship") {
                NavigationLink {
                    DailyCheckInView()
                } label: {
                    Label("Check-In", systemImage: "questionmark.bubble")
                }
                NavigationLink {
                    MilestonesView()
                } label: {
                    Label("Milestones", systemImage: "calendar.badge.plus")
                }
                NavigationLink {
                    StatsView()
                } label: {
                    Label("Insights", systemImage: "chart.bar.xaxis")
                }
            }
            Section("App") {
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .navigationTitle("More")
    }
}
