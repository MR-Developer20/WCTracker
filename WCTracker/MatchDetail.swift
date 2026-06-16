import Foundation

// MARK: - Pitch geometry

/// Normalized pitch coordinate. x runs along the length (0 = left goal line,
/// 1 = right goal line); y runs across the width (0 = top touchline, 1 = bottom).
struct PitchPoint: Equatable {
    var x: Double
    var y: Double
    static let center = PitchPoint(x: 0.5, y: 0.5)
}

/// Position rows used to lay a formation out on the pitch.
enum PitchRole: Int, CaseIterable {
    case gk, def, dm, mid, am, fwd

    /// Depth into a team's own half: 0 = own goal line, ~1 = halfway line.
    var depth: Double {
        switch self {
        case .gk:  return 0.04
        case .def: return 0.40
        case .dm:  return 0.56
        case .mid: return 0.70
        case .am:  return 0.82
        case .fwd: return 0.95
        }
    }
}

// MARK: - Lineups

struct LineupPlayer: Identifiable {
    let id: String
    var name: String        // display name, e.g. "Raúl Jiménez"
    var shortName: String   // e.g. "R. Jiménez"
    var number: String      // jersey
    var positionAbbr: String
    var role: PitchRole
    var point: PitchPoint   // normalized pitch position
    var isHome: Bool
}

struct Lineup: Identifiable {
    var id: String { teamId }
    var teamId: String
    var name: String
    var code: String
    var colorHex: String?
    var formation: String?
    var isHome: Bool
    var starters: [LineupPlayer]
    var substitutes: [LineupPlayer]
}

// MARK: - Events / goals

struct MatchEvent: Identifiable {
    enum Kind { case goal, yellow, red, sub, varReview, whistle, other }

    let id = UUID()
    var minute: Int?
    var clockText: String
    var typeText: String
    var detailText: String?
    var scoringPlay: Bool
    var teamId: String?
    var isHome: Bool?
    var playerName: String?
    var assistName: String?
    var text: String?

    var kind: Kind {
        let t = (typeText + " " + (detailText ?? "")).lowercased()
        if scoringPlay || t.contains("goal") && !t.contains("disallow") { return .goal }
        if t.contains("yellow") { return .yellow }
        if t.contains("red") { return .red }
        if t.contains("sub") { return .sub }
        if t.contains("var") { return .varReview }
        if t.contains("kickoff") || t.contains("half") || t.contains("full time") || t.contains("whistle") { return .whistle }
        return .other
    }
}

struct GoalEvent: Identifiable {
    let id = UUID()
    var minute: Int?
    var clockText: String
    var scorer: String
    var assist: String?
    var isHome: Bool
    var isOwnGoal: Bool
    var isPenalty: Bool
}

// MARK: - Team stats / venue / weather

struct TeamStat: Identifiable {
    var id: String { label }
    var label: String
    var homeText: String
    var awayText: String
    var homeValue: Double?
    var awayValue: Double?
    var isPercent: Bool
}

struct VenueInfo {
    var name: String?
    var city: String?
    var country: String?
    var attendance: Int?

    var locationLine: String {
        [city, country].compactMap { $0 }.joined(separator: ", ")
    }
    /// Best query string for geocoding the venue.
    var geocodeQuery: String? {
        if let city, let country { return "\(city), \(country)" }
        return city ?? country ?? name
    }
}

struct MatchWeather {
    enum Source: String { case weatherKit = "WeatherKit", openMeteo = "Open-Meteo" }
    var temperatureC: Double
    var condition: String
    var symbolName: String
    var windKph: Double?
    var humidity: Int?
    var source: Source

    var temperatureText: String { "\(Int(temperatureC.rounded()))°C" }
}

// MARK: - Aggregate detail

struct MatchDetail {
    var eventId: String
    var homeLineup: Lineup?
    var awayLineup: Lineup?
    var events: [MatchEvent]
    var goals: [GoalEvent]
    var stats: [TeamStat]
    var venue: VenueInfo?

    var hasLineups: Bool { (homeLineup?.starters.isEmpty == false) || (awayLineup?.starters.isEmpty == false) }
    var allPlayers: [LineupPlayer] { (homeLineup?.starters ?? []) + (awayLineup?.starters ?? []) }
}

// MARK: - Pitch layout

enum PitchLayout {
    static func role(for raw: String) -> PitchRole {
        let a = raw.uppercased()
        if a == "G" || a.contains("GK") { return .gk }
        if a.contains("WB") { return .def }                 // wing-backs defend
        if a.hasSuffix("B") || a.hasPrefix("CD") || a.hasPrefix("CB") || a == "D" { return .def }
        if a.hasPrefix("DM") || a.contains("CDM") { return .dm }
        if a.hasPrefix("AM") || a.contains("CAM") { return .am }
        if a.hasPrefix("CM") || a.hasPrefix("LM") || a.hasPrefix("RM") || a == "M" { return .mid }
        return .fwd
    }

    /// Lateral position across the pitch: -2 far-left (full-backs/wingers),
    /// -1 left-leaning (e.g. CD-L), 0 central, +1 right-leaning, +2 far-right.
    /// Used to order a row AND to keep full-backs wide / centre-backs central.
    static func lateral(for raw: String) -> Int {
        let a = raw.uppercased()
        if ["LB", "LWB", "LM", "LW", "LF"].contains(a) { return -2 }
        if ["RB", "RWB", "RM", "RW", "RF"].contains(a) { return 2 }
        if a.hasSuffix("-L") || a.hasPrefix("L") { return -1 }
        if a.hasSuffix("-R") || a.hasPrefix("R") { return 1 }
        return 0
    }

    /// Raw starter info coming out of the ESPN roster.
    struct RawPlayer {
        var id: String
        var name: String
        var shortName: String
        var number: String
        var abbr: String
    }

    /// Distribute starters into formation rows and compute normalized pitch points.
    /// Home defends the left goal (x≈0) and attacks right; away is mirrored.
    static func place(_ raw: [RawPlayer], isHome: Bool) -> [LineupPlayer] {
        var rows: [PitchRole: [RawPlayer]] = [:]
        for p in raw { rows[role(for: p.abbr), default: []].append(p) }

        var result: [LineupPlayer] = []
        for roleRow in PitchRole.allCases {
            guard var players = rows[roleRow], !players.isEmpty else { continue }
            players.sort {
                (lateral(for: $0.abbr), Int($0.number) ?? 99) < (lateral(for: $1.abbr), Int($1.number) ?? 99)
            }
            let depth = roleRow.depth
            let x = isHome ? (0.045 + depth * 0.42) : (0.955 - depth * 0.42)

            // Widen the spread when the row has wide players (full-backs/wingers),
            // and keep central-only rows (e.g. a CB or CM pair) toward the middle.
            let maxAbs = players.map { abs(lateral(for: $0.abbr)) }.max() ?? 0
            let (lo, hi): (Double, Double) = maxAbs >= 2 ? (0.12, 0.88)
                : maxAbs == 1 ? (0.30, 0.70)
                : (0.40, 0.60)

            let n = players.count
            for (i, p) in players.enumerated() {
                let y = n == 1 ? 0.5 : lo + (hi - lo) * Double(i) / Double(n - 1)
                result.append(LineupPlayer(
                    id: p.id, name: p.name, shortName: p.shortName, number: p.number,
                    positionAbbr: p.abbr, role: roleRow,
                    point: PitchPoint(x: x, y: y), isHome: isHome))
            }
        }
        return result
    }
}

// MARK: - Ball estimator (event-driven; no free positional feed exists)

enum BallEstimator {
    /// A plausible normalized ball position derived from the most recent meaningful
    /// event. Home attacks toward x=1, away toward x=0. This is an approximation,
    /// surfaced as such in the UI — not a true tracking feed.
    static func target(events: [MatchEvent], lastIndex: Int?) -> PitchPoint {
        guard let idx = lastIndex, events.indices.contains(idx) else { return .center }
        let e = events[idx]
        guard let isHome = e.isHome else { return .center }
        // Vary the cross-field position deterministically so consecutive events
        // don't stack on one line.
        let jitter = Double((abs(e.id.hashValue) % 50)) / 100.0 + 0.25   // 0.25...0.75
        switch e.kind {
        case .goal:
            return PitchPoint(x: isHome ? 0.95 : 0.05, y: 0.5)
        case .yellow, .red, .other, .sub:
            // foul / play in the offending team's own half-ish
            return PitchPoint(x: isHome ? 0.62 : 0.38, y: jitter)
        case .varReview, .whistle:
            return .center
        }
    }
}

// MARK: - ESPN summary parser

enum ESPNSummaryParser {
    static func parse(_ json: JSONValue, homeTeamId: String, awayTeamId: String, eventId: String) -> MatchDetail {
        let (home, away) = lineups(json, homeTeamId: homeTeamId)
        let events = self.events(json, homeTeamId: homeTeamId)
        return MatchDetail(
            eventId: eventId,
            homeLineup: home,
            awayLineup: away,
            events: events,
            goals: goals(from: events),
            stats: stats(json, homeTeamId: homeTeamId),
            venue: venue(json)
        )
    }

    // MARK: Lineups

    private static func lineups(_ json: JSONValue, homeTeamId: String) -> (home: Lineup?, away: Lineup?) {
        var home: Lineup?
        var away: Lineup?
        for entry in json.field(["rosters"])?.arrayValue ?? [] {
            guard let team = entry.field(["team"]) else { continue }
            let teamId = team.string("id") ?? ""
            let isHome = entry.string("homeAway") == "home" || teamId == homeTeamId
            let code = (team.string("abbreviation") ?? "").uppercased()

            var starters: [PitchLayout.RawPlayer] = []
            var subs: [LineupPlayer] = []
            for p in entry.field(["roster"])?.arrayValue ?? [] {
                let athlete = p.field(["athlete"])
                let name = athlete?.string("displayName") ?? athlete?.string("shortName") ?? "—"
                let shortName = athlete?.string("shortName") ?? name
                let pid = athlete?.string("id") ?? UUID().uuidString
                let number = p.string("jersey") ?? ""
                let abbr = p.field(["position"])?.string("abbreviation") ?? ""
                if p.bool("starter") == true {
                    starters.append(.init(id: pid, name: name, shortName: shortName, number: number, abbr: abbr))
                } else {
                    subs.append(LineupPlayer(id: pid, name: name, shortName: shortName, number: number,
                                             positionAbbr: abbr, role: PitchLayout.role(for: abbr),
                                             point: .center, isHome: isHome))
                }
            }

            let lineup = Lineup(
                teamId: teamId,
                name: team.string("displayName", "name") ?? code,
                code: code,
                colorHex: team.string("color"),
                formation: entry.string("formation"),
                isHome: isHome,
                starters: PitchLayout.place(starters, isHome: isHome),
                substitutes: subs)
            if isHome { home = lineup } else { away = lineup }
        }
        return (home, away)
    }

    // MARK: Events

    private static func leadingInt(_ s: String?) -> Int? {
        guard let s else { return nil }
        let digits = s.prefix { $0.isNumber }
        return Int(digits)
    }

    private static func events(_ json: JSONValue, homeTeamId: String) -> [MatchEvent] {
        (json.field(["keyEvents"])?.arrayValue ?? []).map { e in
            let clock = e.field(["clock"])?.string("displayValue") ?? ""
            let teamId = e.field(["team"])?.string("id")
            let participants = e.field(["participants"])?.arrayValue ?? []
            let player = participants.first?.field(["athlete"])?.string("displayName", "shortName")
            let assist = participants.count > 1 ? participants[1].field(["athlete"])?.string("displayName", "shortName") : nil
            return MatchEvent(
                minute: leadingInt(clock),
                clockText: clock,
                typeText: e.field(["type"])?.string("text") ?? "",
                detailText: e.string("shortText"),
                scoringPlay: e.bool("scoringPlay") ?? false,
                teamId: teamId,
                isHome: teamId.map { $0 == homeTeamId },
                playerName: player,
                assistName: assist,
                text: e.string("text"))
        }
    }

    private static func goals(from events: [MatchEvent]) -> [GoalEvent] {
        events.filter { $0.kind == .goal }.map { e in
            let lower = (e.text ?? "").lowercased()
            return GoalEvent(
                minute: e.minute,
                clockText: e.clockText,
                scorer: e.playerName ?? "—",
                assist: e.assistName,
                isHome: e.isHome ?? false,
                isOwnGoal: lower.contains("own goal"),
                isPenalty: lower.contains("penalty"))
        }
    }

    // MARK: Stats

    private static let curatedStats: [(key: String, label: String, percent: Bool)] = [
        ("possessionPct", "Possession", true),
        ("totalShots", "Shots", false),
        ("shotsOnTarget", "Shots on Target", false),
        ("wonCorners", "Corners", false),
        ("foulsCommitted", "Fouls", false),
        ("offsides", "Offsides", false),
        ("saves", "Saves", false),
        ("accuratePasses", "Accurate Passes", false),
        ("yellowCards", "Yellow Cards", false),
    ]

    private static func stats(_ json: JSONValue, homeTeamId: String) -> [TeamStat] {
        var homeMap: [String: String] = [:]
        var awayMap: [String: String] = [:]
        for team in json.field(["boxscore"])?.field(["teams"])?.arrayValue ?? [] {
            let teamId = team.field(["team"])?.string("id") ?? ""
            let isHome = team.string("homeAway") == "home" || teamId == homeTeamId
            var map: [String: String] = [:]
            for stat in team.field(["statistics"])?.arrayValue ?? [] {
                if let name = stat.string("name"), let value = stat.string("displayValue") {
                    map[name] = value
                }
            }
            if isHome { homeMap = map } else { awayMap = map }
        }
        return curatedStats.compactMap { spec in
            let h = homeMap[spec.key]
            let a = awayMap[spec.key]
            guard h != nil || a != nil else { return nil }
            func num(_ s: String?) -> Double? { s.flatMap { Double($0.replacingOccurrences(of: "%", with: "")) } }
            func text(_ s: String?) -> String {
                guard let s else { return "–" }
                return spec.percent ? "\(s)%" : s
            }
            return TeamStat(label: spec.label, homeText: text(h), awayText: text(a),
                            homeValue: num(h), awayValue: num(a), isPercent: spec.percent)
        }
    }

    // MARK: Venue

    private static func venue(_ json: JSONValue) -> VenueInfo? {
        let gameInfo = json.field(["gameInfo"])
        let venue = gameInfo?.field(["venue"])
        let address = venue?.field(["address"])
        return VenueInfo(
            name: venue?.string("fullName", "shortName"),
            city: address?.string("city"),
            country: address?.string("country"),
            attendance: gameInfo?.int("attendance"))
    }
}
