import Foundation

// MARK: - Pitch geometry

/// Normalized pitch coordinate. x runs along the length (0 = left goal line,
/// 1 = right goal line); y runs across the width (0 = top touchline, 1 = bottom).
struct PitchPoint: Equatable {
    var x: Double
    var y: Double
    static let center = PitchPoint(x: 0.5, y: 0.5)
}

/// A located on-ball event used to build the possession heat map (team-relative,
/// canonical orientation — home attacks right).
struct HeatPoint {
    var point: PitchPoint
    var isHome: Bool
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

struct PlayerStat: Identifiable {
    var id: String { label }
    var label: String       // stat abbreviation, e.g. "G", "SHT"
    var name: String        // full stat name, e.g. "Goals"
    var value: String
}

struct LineupPlayer: Identifiable {
    let id: String
    var name: String        // display name, e.g. "Raúl Jiménez"
    var shortName: String   // e.g. "R. Jiménez"
    var number: String      // jersey
    var positionAbbr: String
    var role: PitchRole
    var point: PitchPoint   // normalized pitch position
    var isHome: Bool
    var headshotURL: URL? = nil
    var subbedOut: Bool = false
    var subbedIn: Bool = false
    var formationPlace: Int? = nil
    var stats: [PlayerStat] = []
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

/// An on-ball play with a real pitch location from ESPN's `commentary` feed.
struct PlayPoint: Identifiable {
    let id = UUID()
    var minute: Int
    var clockText: String
    var typeText: String
    var isHome: Bool?
    var text: String?
    var point: PitchPoint   // normalized, canonical orientation (home attacks right)
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

    var temperatureText: String { TemperatureUnit.celsius.display(celsius: temperatureC) }
}

/// User-selectable temperature unit for the weather card.
enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius = "°C"
    case fahrenheit = "°F"
    var id: String { rawValue }

    func display(celsius: Double) -> String {
        switch self {
        case .celsius: return "\(Int(celsius.rounded()))°C"
        case .fahrenheit: return "\(Int((celsius * 9 / 5 + 32).rounded()))°F"
        }
    }
}

// MARK: - Format & officials

/// Match format from ESPN `format.regulation` — used to drive the clock/ET logic.
struct MatchFormat {
    var periods: Int        // regulation periods (e.g. 2)
    var halfMinutes: Int    // minutes per period (e.g. 45)
    var regulationMinutes: Int { periods * halfMinutes }   // e.g. 90
    var summary: String { "\(periods) × \(halfMinutes)'" }
}

struct Official: Identifiable {
    let id = UUID()
    var name: String
    var role: String
}

// MARK: - Leaders / broadcasts / media

struct StatLeader: Identifiable {
    let id = UUID()
    var category: String
    var player: String
    var value: String
}

struct TeamLeaders: Identifiable {
    var id: String { code }
    var code: String
    var isHome: Bool
    var entries: [StatLeader]
}

struct Broadcast: Identifiable {
    let id = UUID()
    var name: String
    var kind: String   // "TV" / "Streaming" / …
}

struct NewsItem: Identifiable {
    let id = UUID()
    var headline: String
    var url: URL?
}

struct VideoItem: Identifiable {
    let id = UUID()
    var headline: String
    var url: URL?
    var thumbnail: URL?
    var duration: Int?
}

// MARK: - Configurable info cards

/// The cards shown in the right info panel; user-orderable / hideable.
enum InfoCardKind: String, CaseIterable, Identifiable, Codable {
    case goals, teamStats, stadium, officials, weather, events, leaders, broadcasts, news, videos
    var id: String { rawValue }

    var title: String {
        switch self {
        case .goals: return "Goals"
        case .teamStats: return "Team Stats"
        case .stadium: return "Stadium"
        case .officials: return "Officials"
        case .weather: return "Weather"
        case .events: return "Match Events"
        case .leaders: return "Leaders"
        case .broadcasts: return "Where to Watch"
        case .news: return "News"
        case .videos: return "Videos"
        }
    }

    var systemImage: String {
        switch self {
        case .goals: return "soccerball.inverse"
        case .teamStats: return "chart.bar.xaxis"
        case .stadium: return "sportscourt"
        case .officials: return "whistle"
        case .weather: return "cloud.sun"
        case .events: return "list.bullet.rectangle"
        case .leaders: return "star.circle"
        case .broadcasts: return "tv"
        case .news: return "newspaper"
        case .videos: return "play.rectangle"
        }
    }
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
    var format: MatchFormat? = nil
    var officials: [Official] = []
    var leaders: [TeamLeaders] = []
    var broadcasts: [Broadcast] = []
    var articles: [NewsItem] = []
    var videos: [VideoItem] = []
    /// On-ball plays with real pitch coordinates (ESPN commentary), oldest → newest.
    var plays: [PlayPoint] = []

    var hasLineups: Bool { (homeLineup?.starters.isEmpty == false) || (awayLineup?.starters.isEmpty == false) }
    var allPlayers: [LineupPlayer] { (homeLineup?.starters ?? []) + (awayLineup?.starters ?? []) }
    /// The most recent real ball location (nil if the feed has no coordinates yet).
    var ballPoint: PitchPoint? { plays.last?.point }
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
        var headshotURL: URL? = nil
        var subbedOut: Bool = false
        var subbedIn: Bool = false
        var formationPlace: Int? = nil
        var stats: [PlayerStat] = []
    }

    private static func x(forDepth depth: Double, isHome: Bool) -> Double {
        isHome ? (0.045 + depth * 0.42) : (0.955 - depth * 0.42)
    }

    private static func make(_ p: RawPlayer, isHome: Bool, x: Double, y: Double) -> LineupPlayer {
        LineupPlayer(
            id: p.id, name: p.name, shortName: p.shortName, number: p.number,
            positionAbbr: p.abbr, role: role(for: p.abbr),
            point: PitchPoint(x: x, y: y), isHome: isHome,
            headshotURL: p.headshotURL, subbedOut: p.subbedOut, subbedIn: p.subbedIn,
            formationPlace: p.formationPlace, stats: p.stats)
    }

    /// Outfield line sizes from the formation string ("4-2-3-1" → [4,2,3,1]); nil/
    /// mismatched returns [] so the caller falls back to role buckets.
    private static func formationLines(_ formation: String?, count: Int) -> [Int] {
        guard let formation else { return [] }
        let sizes = formation.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        return sizes.reduce(0, +) == count && !sizes.isEmpty ? sizes : []
    }

    /// Lay players out from the declared formation so the shape is exact (a 4-2-3-1
    /// shows as 4-2-3-1). Home defends the left goal (x≈0) and attacks right.
    static func place(_ raw: [RawPlayer], isHome: Bool, formation: String?) -> [LineupPlayer] {
        let keepers = raw.filter { role(for: $0.abbr) == .gk }
        var outfield = raw.filter { role(for: $0.abbr) != .gk }
        let lines = formationLines(formation, count: outfield.count)
        guard !lines.isEmpty else { return placeByRole(raw, isHome: isHome) }

        // Order outfield from defenders → forwards so the back-most fill the first line.
        outfield.sort {
            (role(for: $0.abbr).rawValue, formationPlaceOrder($0)) < (role(for: $1.abbr).rawValue, formationPlaceOrder($1))
        }

        var result = keepers.map { make($0, isHome: isHome, x: x(forDepth: 0.0, isHome: isHome), y: 0.5) }
        let lineCount = lines.count
        var i = 0
        for (li, size) in lines.enumerated() {
            var linePlayers = Array(outfield[i..<min(i + size, outfield.count)])
            i += size
            linePlayers.sort { (lateral(for: $0.abbr), formationPlaceOrder($0)) < (lateral(for: $1.abbr), formationPlaceOrder($1)) }
            let depth = lineCount == 1 ? 0.7 : 0.40 + (0.96 - 0.40) * Double(li) / Double(lineCount - 1)
            let px = x(forDepth: depth, isHome: isHome)
            let maxAbs = linePlayers.map { abs(lateral(for: $0.abbr)) }.max() ?? 0
            let (lo, hi): (Double, Double) = linePlayers.count >= 4 ? (0.10, 0.90)
                : maxAbs >= 2 ? (0.14, 0.86)
                : maxAbs == 1 ? (0.30, 0.70)
                : (0.40, 0.60)
            let n = linePlayers.count
            for (j, p) in linePlayers.enumerated() {
                let y = n == 1 ? 0.5 : lo + (hi - lo) * Double(j) / Double(n - 1)
                result.append(make(p, isHome: isHome, x: px, y: y))
            }
        }
        return result
    }

    private static func formationPlaceOrder(_ p: RawPlayer) -> Int { p.formationPlace ?? (Int(p.number) ?? 99) }

    /// Fallback when the formation string is missing/inconsistent: bucket by role.
    private static func placeByRole(_ raw: [RawPlayer], isHome: Bool) -> [LineupPlayer] {
        var rows: [PitchRole: [RawPlayer]] = [:]
        for p in raw { rows[role(for: p.abbr), default: []].append(p) }
        var result: [LineupPlayer] = []
        for roleRow in PitchRole.allCases {
            guard var players = rows[roleRow], !players.isEmpty else { continue }
            players.sort { (lateral(for: $0.abbr), formationPlaceOrder($0)) < (lateral(for: $1.abbr), formationPlaceOrder($1)) }
            let px = x(forDepth: roleRow.depth, isHome: isHome)
            let maxAbs = players.map { abs(lateral(for: $0.abbr)) }.max() ?? 0
            let (lo, hi): (Double, Double) = maxAbs >= 2 ? (0.12, 0.88) : maxAbs == 1 ? (0.30, 0.70) : (0.40, 0.60)
            let n = players.count
            for (j, p) in players.enumerated() {
                let y = n == 1 ? 0.5 : lo + (hi - lo) * Double(j) / Double(n - 1)
                result.append(make(p, isHome: isHome, x: px, y: y))
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
            venue: venue(json),
            format: format(json),
            officials: officials(json),
            leaders: leaders(json, homeTeamId: homeTeamId),
            broadcasts: broadcasts(json),
            articles: articles(json),
            videos: videos(json),
            plays: plays(json, homeTeamId: homeTeamId)
        )
    }

    // MARK: Format & officials

    private static func format(_ json: JSONValue) -> MatchFormat? {
        guard let reg = json.field(["format"])?.field(["regulation"]) else { return nil }
        let periods = reg.int("periods") ?? 2
        let clock = reg.field(["clock"])?.doubleValue ?? 2700
        return MatchFormat(periods: periods, halfMinutes: Int((clock / 60).rounded()))
    }

    private static func officials(_ json: JSONValue) -> [Official] {
        (json.field(["gameInfo"])?.field(["officials"])?.arrayValue ?? []).compactMap { o in
            guard let name = o.string("displayName", "fullName") else { return nil }
            return Official(name: name, role: o.field(["position"])?.string("displayName", "name") ?? "Official")
        }
    }

    // MARK: Leaders / broadcasts / media

    private static func leaders(_ json: JSONValue, homeTeamId: String) -> [TeamLeaders] {
        (json.field(["leaders"])?.arrayValue ?? []).compactMap { group in
            let team = group.field(["team"])
            let code = (team?.string("abbreviation") ?? "").uppercased()
            let isHome = team?.string("id") == homeTeamId
            let entries = (group.field(["leaders"])?.arrayValue ?? []).compactMap { cat -> StatLeader? in
                guard let top = cat.field(["leaders"])?.arrayValue?.first,
                      let value = top.string("displayValue") else { return nil }
                let player = top.field(["athlete"])?.string("displayName", "shortName") ?? "—"
                return StatLeader(category: cat.string("displayName", "name") ?? "", player: player, value: value)
            }
            guard !entries.isEmpty else { return nil }
            return TeamLeaders(code: code, isHome: isHome, entries: entries)
        }
    }

    private static func broadcasts(_ json: JSONValue) -> [Broadcast] {
        var seen = Set<String>()
        return (json.field(["broadcasts"])?.arrayValue ?? []).compactMap { b in
            guard let name = b.field(["media"])?.string("name", "shortName", "callLetters") else { return nil }
            guard seen.insert(name).inserted else { return nil }
            return Broadcast(name: name, kind: (b.field(["type"])?.string("longName", "shortName") ?? "TV").capitalized)
        }
    }

    private static func articles(_ json: JSONValue) -> [NewsItem] {
        (json.field(["news"])?.field(["articles"])?.arrayValue ?? []).compactMap { a in
            guard let headline = a.string("headline", "description") else { return nil }
            let url = a.field(["links"])?.field(["web"])?.string("href").flatMap { URL(string: $0) }
            return NewsItem(headline: headline, url: url)
        }
    }

    private static func videos(_ json: JSONValue) -> [VideoItem] {
        (json.field(["videos"])?.arrayValue ?? []).compactMap { v in
            guard let headline = v.string("headline", "description") else { return nil }
            let links = v.field(["links"])
            let url = (links?.field(["web"])?.string("href") ?? links?.field(["source"])?.string("href"))
                .flatMap { URL(string: $0) }
            return VideoItem(headline: headline,
                             url: url,
                             thumbnail: v.string("thumbnail").flatMap { URL(string: $0) },
                             duration: v.int("duration"))
        }
    }

    // MARK: Ball plays (real coordinates from `commentary`)

    /// ESPN reports `fieldPositionX/Y` (start) and `fieldPosition2X/2Y` (end) on a
    /// 0–100 grid, *team-relative* (x=100 = the team's attacking goal). Convert to a
    /// canonical pitch where the home team attacks right; the half-switch is applied
    /// separately by the view. Returns plays oldest → newest.
    private static func plays(_ json: JSONValue, homeTeamId: String) -> [PlayPoint] {
        var indexed: [(key: (Double, Int), play: PlayPoint)] = []
        for (i, entry) in (json.field(["commentary"])?.arrayValue ?? []).enumerated() {
            guard let play = entry.field(["play"]),
                  let x = play.field(["fieldPositionX"])?.doubleValue,
                  let y = play.field(["fieldPositionY"])?.doubleValue else { continue }
            // Prefer the end location (where the ball finished).
            let ex = play.field(["fieldPosition2X"])?.doubleValue ?? x
            let ey = play.field(["fieldPosition2Y"])?.doubleValue ?? y
            let isHome = play.field(["team"])?.string("id").map { $0 == homeTeamId }
            let cx = (isHome ?? true) ? ex / 100 : 1 - ex / 100
            let cy = ey / 100
            let clockVal = play.field(["clock"])?.field(["value"])?.doubleValue ?? 0
            let clockText = play.field(["clock"])?.string("displayValue")
                ?? entry.field(["time"])?.string("displayValue") ?? ""
            indexed.append((
                key: (clockVal, i),
                play: PlayPoint(
                    minute: leadingInt(clockText) ?? Int(clockVal / 60),
                    clockText: clockText,
                    typeText: play.field(["type"])?.string("text") ?? "",
                    isHome: isHome,
                    text: play.string("text") ?? entry.string("text"),
                    point: PitchPoint(x: min(1, max(0, cx)), y: min(1, max(0, cy))))
            ))
        }
        return indexed.sorted { $0.key < $1.key }.map(\.play)
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

            let formation = entry.string("formation")
            var starters: [PitchLayout.RawPlayer] = []
            var subs: [LineupPlayer] = []
            for p in entry.field(["roster"])?.arrayValue ?? [] {
                let athlete = p.field(["athlete"])
                let name = athlete?.string("displayName") ?? athlete?.string("shortName") ?? "—"
                let shortName = athlete?.string("shortName") ?? name
                let pid = athlete?.string("id") ?? UUID().uuidString
                let number = p.string("jersey") ?? ""
                let abbr = p.field(["position"])?.string("abbreviation") ?? ""
                let headshot = athlete?.field(["headshot"])?.string("href").flatMap { URL(string: $0) }
                let subbedOut = p.bool("subbedOut") ?? false
                let subbedIn = p.bool("subbedIn") ?? false
                let place = p.int("formationPlace")
                let stats = (p.field(["stats"])?.arrayValue ?? []).compactMap { s -> PlayerStat? in
                    guard let v = s.string("displayValue") else { return nil }
                    let abbr = s.string("abbreviation") ?? s.string("name") ?? ""
                    return PlayerStat(label: abbr, name: s.string("name") ?? abbr, value: v)
                }
                if p.bool("starter") == true {
                    starters.append(.init(id: pid, name: name, shortName: shortName, number: number, abbr: abbr,
                                          headshotURL: headshot, subbedOut: subbedOut, subbedIn: subbedIn,
                                          formationPlace: place, stats: stats))
                } else {
                    subs.append(LineupPlayer(id: pid, name: name, shortName: shortName, number: number,
                                             positionAbbr: abbr, role: PitchLayout.role(for: abbr),
                                             point: .center, isHome: isHome,
                                             headshotURL: headshot, subbedOut: subbedOut, subbedIn: subbedIn,
                                             formationPlace: place, stats: stats))
                }
            }

            let lineup = Lineup(
                teamId: teamId,
                name: team.string("displayName", "name") ?? code,
                code: code,
                colorHex: team.string("color"),
                formation: formation,
                isHome: isHome,
                starters: PitchLayout.place(starters, isHome: isHome, formation: formation),
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
