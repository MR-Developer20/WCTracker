import SwiftUI

@main
struct WCTrackerApp: App {
    @StateObject private var tournament: TournamentStore
    @StateObject private var center: MatchCenterStore

    init() {
        let store = TournamentStore()
        _tournament = StateObject(wrappedValue: store)
        _center = StateObject(wrappedValue: MatchCenterStore(tournament: store))
    }

    var body: some Scene {
        WindowGroup {
            SecondScreenView(center: center)
                .task {
                    tournament.start()
                    center.start()
                }
        }
    }
}
