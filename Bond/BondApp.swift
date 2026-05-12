import SwiftUI

@main
struct BondApp: App {
    @State private var supabase = SupabaseService.shared
    @State private var pairingService: PairingService
    @State private var reminderRepo: ReminderRepository

    init() {
        let pairing = PairingService()
        _pairingService = State(initialValue: pairing)
        _reminderRepo = State(initialValue: ReminderRepository(pairing: pairing))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(supabase)
                .environment(pairingService)
                .environment(reminderRepo)
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
                ReminderListView()
            }
        }
        .task {
            await pairing.loadCouple()
        }
    }
}
