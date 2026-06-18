import Foundation

/// Single shared owner of the data stores so the SwiftUI window scene and the
/// CarPlay scene render the same live match from one polling loop. The CarPlay
/// scene delegate lives outside the SwiftUI `App`, so it can't reach the stores
/// built in `WCTrackerApp.init()` — this gives both scenes one source of truth.
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let tournament: TournamentStore
    let center: MatchCenterStore

    private var started = false

    private init() {
        let store = TournamentStore()
        tournament = store
        center = MatchCenterStore(tournament: store)
    }

    /// Begin polling / detail refresh. Idempotent, so every scene that connects
    /// (phone window, CarPlay) can call it without restarting the loops.
    func startIfNeeded() {
        guard !started else { return }
        started = true
        tournament.start()
        center.start()
    }
}
