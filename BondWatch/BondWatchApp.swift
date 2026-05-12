import SwiftUI

@main
struct BondWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}

struct WatchRootView: View {
    var body: some View {
        NavigationStack {
            List {
                ContentUnavailableView(
                    "Bond",
                    systemImage: "heart.fill",
                    description: Text("Reminders + dictation arrive in Phase 3.")
                )
            }
            .navigationTitle("Bond")
        }
    }
}
