import SwiftUI

@main
struct BondApp: App {
    @State private var supabase = SupabaseService.shared
    @State private var store = PurchasesService.shared
    @State private var pairingService: PairingService
    @State private var reminderRepo: ReminderRepository
    @State private var milestonesService: MilestonesService

    init() {
        let pairing = PairingService()
        let repo = ReminderRepository(pairing: pairing)
        let milestones = MilestonesService(pairing: pairing)

        _pairingService = State(initialValue: pairing)
        _reminderRepo = State(initialValue: repo)
        _milestonesService = State(initialValue: milestones)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(supabase)
                .environment(store)
                .environment(pairingService)
                .environment(reminderRepo)
                .environment(milestonesService)
                .onAppear {
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
        }
    }
}

struct RootView: View {
    @Environment(SupabaseService.self) private var supabase
    @Environment(PairingService.self) private var pairing
    @State private var isTransitioning = false

    var body: some View {
        Group {
            switch currentDestination {
            case .onboarding:
                OnboardingView()
                    .transition(.opacity)
            case .preference:
                PreferenceChoiceView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            case .pairing:
                PairingView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            case .home:
                HomeTabs()
                    .transition(.opacity)
            case .loading:
                ZStack {
                    Color(.systemBackground).ignoresSafeArea()
                    ProgressView()
                        .controlSize(.large)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.35), value: currentDestination)
        .task {
            if supabase.isAuthenticated {
                isTransitioning = true
            }
            await pairing.loadCouple()
            isTransitioning = false
        }
        .onChange(of: supabase.isAuthenticated) { _, authenticated in
            guard authenticated else { return }
            isTransitioning = true
            Task {
                await pairing.loadCouple()
                isTransitioning = false
            }
        }
    }

    private enum Destination { case onboarding, loading, preference, pairing, home }

    private var currentDestination: Destination {
        if isTransitioning {
            return .loading
        }
        if !supabase.isAuthenticated {
            return .onboarding
        }
        if pairing.needsPreferenceChoice {
            return .preference
        }
        if pairing.coupleId == nil {
            return .pairing
        }
        return .home
    }
}

struct HomeTabs: View {
    var body: some View {
        TabView {
            ReminderListView()
                .tabItem { Label("Reminders", systemImage: "heart.text.square") }
            MilestonesView()
                .tabItem { Label("Milestones", systemImage: "calendar.badge.plus") }
            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.bar.xaxis") }
        }
    }
}
