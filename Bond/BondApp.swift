import SwiftUI

@main
struct BondApp: App {
    @State private var supabase = SupabaseService.shared
    @State private var pairingService = PairingService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(supabase)
                .environment(pairingService)
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
                HomeView()
            }
        }
        .task {
            await pairing.loadCouple()
        }
    }
}

struct HomeView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "You're paired",
                systemImage: "heart.fill",
                description: Text("Reminder list lands here in Phase 2.")
            )
            .navigationTitle("Bond")
        }
    }
}
