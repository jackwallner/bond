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

    var body: some View {
        Group {
            if !supabase.isAuthenticated {
                OnboardingView()
            } else if pairing.coupleId == nil {
                PairingView()
            } else {
                HomeTabs()
            }
        }
        .task {
            await pairing.loadCouple()
        }
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
