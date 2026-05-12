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
            DictateView()
        }
    }
}
