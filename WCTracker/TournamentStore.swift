import Foundation
import Combine

enum StoreStatus: Equatable {
    case connecting, connected, error(String)
    var label: String {
        switch self {
        case .connecting: return "Connecting…"
        case .connected: return "Live"
        case .error(let m): return m
        }
    }
}

/// Slim, iOS-only port of the macOS app's store: polls ESPN's free FIFA World Cup
/// feed for the scoreboard, standings (teams/groups) and derives stadiums.
@MainActor
final class TournamentStore: ObservableObject {
    @Published var teams: [Team] = []
    @Published var groups: [TournamentGroup] = []
    @Published var matches: [Match] = []
    @Published var stadiums: [Stadium] = []
    @Published var status: StoreStatus = .connecting
    @Published var lastUpdated: Date?

    private let client = ESPNAPIClient(baseURL: URL(string: APIConfig.espnBase)!)
    private var pollTimer: Timer?
    private var isRefreshing = false
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        pollTimer?.invalidate()
        // ESPN is unofficial with no published limit and refreshes on a ~10-20s
        // cadence; poll about as fast as that to keep the scorebug score/clock fresh.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        Task { await refresh() }
    }

    func refresh() async {
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            async let t = client.teams()
            async let g = client.groups()
            async let m = client.matches()
            let (teams, groups, matches) = try await (t, g, m)
            self.teams = teams
            self.groups = groups
            let anchored = Self.preservingClockAnchors(new: matches, previous: self.matches)
            self.matches = anchored.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
            self.stadiums = Self.deriveStadiums(from: matches)
            self.lastUpdated = Date()
            self.status = .connected
        } catch {
            if self.matches.isEmpty { self.status = .error(error.localizedDescription) }
        }
    }

    // MARK: Lookups

    func team(id: String) -> Team? { teams.first { $0.id == id } }

    func team(for match: Match, home: Bool) -> Team {
        let id = home ? match.homeTeamId : match.awayTeamId
        var result: Team
        if let found = team(id: id) {
            result = found
        } else {
            let name = (home ? match.homeName : match.awayName) ?? "TBD"
            let code = FlagBook.code(forName: name) ?? String(name.prefix(3)).uppercased()
            result = Team(id: id, name: name, code: code)
        }
        if result.colorHex == nil { result.colorHex = home ? match.homeColorHex : match.awayColorHex }
        // Prefer the API's flag image (ESPN team.logo) over the derived CDN/emoji.
        if let logo = home ? match.homeLogoURL : match.awayLogoURL { result.flagURL = logo }
        return result
    }

    func stadium(id: String?) -> Stadium? {
        guard let id else { return nil }
        return stadiums.first { $0.id == id }
    }

    var liveMatches: [Match] {
        let now = Date()
        return matches.filter { $0.phase(now: now) == .live }
    }

    /// Keep the live clock ticking smoothly across polls (carry the prior anchor
    /// forward while the feed minute is unchanged). Ported from the macOS store.
    private static func preservingClockAnchors(new: [Match], previous: [Match]) -> [Match] {
        let prior = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return new.map { match in
            guard let minute = match.minute, minute > 0,
                  let old = prior[match.id], old.minute == minute,
                  let anchor = old.fetchedAt else { return match }
            var carried = match
            // Carry the original anchor (time + seconds) so the clock keeps ticking
            // from where it was instead of snapping back each poll.
            carried.fetchedAt = anchor
            carried.clockSeconds = old.clockSeconds ?? carried.clockSeconds
            return carried
        }
    }

    private static func deriveStadiums(from matches: [Match]) -> [Stadium] {
        var seen = Set<String>()
        var stadiums: [Stadium] = []
        for match in matches {
            guard let name = match.venueName else { continue }
            let key = match.stadiumId ?? name
            if seen.insert(key).inserted {
                stadiums.append(Stadium(id: key, name: name, city: nil, country: nil, capacity: nil))
            }
        }
        return stadiums.sorted { $0.name < $1.name }
    }
}
