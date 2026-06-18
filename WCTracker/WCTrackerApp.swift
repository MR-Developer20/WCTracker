import SwiftUI

@main
struct WCTrackerApp: App {
    @StateObject private var center: MatchCenterStore

    init() {
        // Stores are owned by AppEnvironment so the CarPlay scene shares them.
        _center = StateObject(wrappedValue: AppEnvironment.shared.center)
    }

    var body: some Scene {
        WindowGroup {
            SecondScreenView(center: center)
                .task { AppEnvironment.shared.startIfNeeded() }
        }
    }
}
