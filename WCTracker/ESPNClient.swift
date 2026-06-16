import Foundation

/// Lightweight transport error (ported from the macOS app's APIClient).
struct APIError: LocalizedError {
    var message: String
    var isAuthFailure = false
    var isNotFound = false
    var errorDescription: String? { message }
}

/// What the store needs from any tournament backend, so it can swap between the
/// ESPN live feed and a custom path-based (emrbli / legacy JWT) backend.
protocol TournamentDataSource {
    func teams() async throws -> [Team]
    func groups() async throws -> [TournamentGroup]
    func matches() async throws -> [Match]
    func stadiums() async throws -> [Stadium]
}

/// Parsing for ESPN's (unofficial) site API for the FIFA World Cup, kept free of
/// networking/protocol dependencies so it can be unit-tested standalone.
///
/// Shapes (free, no auth, near-real-time — the same feed ESPN.com uses):
///  - scoreboard: { events: [{ id, date, competitions: [{
///        competitors: [{ homeAway: home|away, score, team: { id, displayName, abbreviation, logo } }],
///        status: { displayClock: "67'"|"90'+3'", type: { state: pre|in|post, completed } },
///        venue: { id, fullName },
///        details: [{ scoringPlay, type: { text }, clock: { displayValue }, team: { id },
///                    athletesInvolved: [{ shortName }], ownGoal, penaltyKick }] }] }] }
///  - standings: { children: [{ name: "Group A", standings: { entries: [{
///        team: { id, displayName, abbreviation }, stats: [{ name, value }] }] } }] }
enum ESPNParser {
    // MARK: Matches (scoreboard)

    static func matches(_ json: JSONValue, fetchedAt: Date = Date()) -> [Match] {
        (json.field(["events"])?.arrayValue ?? []).compactMap { event in
            guard case .object = event,
                  let comp = event.field(["competitions"])?.arrayValue?.first else { return nil }

            let competitors = comp.field(["competitors"])?.arrayValue ?? []
            func side(_ which: String) -> JSONValue? { competitors.first { $0.string("homeAway") == which } }
            guard let home = side("home"), let away = side("away") else { return nil }

            func teamId(_ side: JSONValue) -> String { side.field(["team"])?.string("id") ?? "" }
            func teamName(_ side: JSONValue) -> String? {
                side.field(["team"])?.string("displayName", "name", "shortDisplayName")
            }

            // state: pre → scheduled, in → live, post → finished. Normalize to a
            // statusText the store's Match.phase() understands.
            let status = comp.field(["status"]) ?? event.field(["status"])
            let type = status?.field(["type"])
            let state = type?.string("state") ?? "pre"
            let isLive = state == "in"
            let isFinished = state == "post"
            let statusText = isLive ? "live" : (isFinished ? "finished" : "scheduled")
            // Halftime is still state "in", distinguished only by the type name/detail.
            // The feed freezes displayClock at "45'+x" for the whole break, so the
            // clock must hold at "HT" rather than tick on from the anchored minute.
            let isHalftime = isLive && (type?.string("name") == "STATUS_HALFTIME" || type?.string("detail") == "HT")

            // Live minute from displayClock: "67'" → 67, "90'+3'" → minute 90, +3.
            let displayClock = status?.string("displayClock")
            let minute = displayClock.flatMap { Int($0.prefix(while: { $0.isNumber })) }
            let plus = displayClock.flatMap { str -> Int? in
                guard let plusIndex = str.firstIndex(of: "+") else { return nil }
                return Int(str[str.index(after: plusIndex)...].prefix(while: { $0.isNumber }))
            }

            var match = Match(
                id: event.string("id") ?? UUID().uuidString,
                homeTeamId: teamId(home),
                awayTeamId: teamId(away),
                homeName: teamName(home),
                awayName: teamName(away),
                homeScore: home.int("score") ?? 0,
                awayScore: away.int("score") ?? 0,
                date: event.string("date").flatMap(Match.parseDate),
                stadiumId: comp.field(["venue"])?.string("id"),
                finishedFlag: isFinished,
                statusText: statusText,
                scorers: scorers(comp, competitors: competitors),
                minute: isLive ? minute : nil,
                venueName: comp.field(["venue"])?.string("fullName"),
                stoppagePlus: isLive ? plus : nil
            )
            // Anchor the live clock so the minute ticks between polls.
            if isLive { match.fetchedAt = fetchedAt }
            match.isHalftime = isHalftime
            // Team kit colors live on the scoreboard feed (the standings endpoint omits them).
            match.homeColorHex = home.field(["team"])?.string("color")
            match.awayColorHex = away.field(["team"])?.string("color")
            // Country flag/crest images from the API (team.logo).
            match.homeLogoURL = home.field(["team"])?.string("logo").flatMap { URL(string: $0) }
            match.awayLogoURL = away.field(["team"])?.string("logo").flatMap { URL(string: $0) }
            return match
        }
    }

    /// Goal events from `competition.details`, formatted "Player 27' (ABBR)".
    private static func scorers(_ comp: JSONValue, competitors: [JSONValue]) -> [String] {
        var abbr: [String: String] = [:]   // team id → abbreviation, for the "(ABBR)" suffix
        for c in competitors {
            if let id = c.field(["team"])?.string("id") {
                abbr[id] = c.field(["team"])?.string("abbreviation")
            }
        }
        var out: [String] = []
        for detail in comp.field(["details"])?.arrayValue ?? [] {
            guard detail.bool("scoringPlay") == true else { continue }
            let player = detail.field(["athletesInvolved"])?.arrayValue?.first?.string("shortName", "displayName") ?? "?"
            let time = detail.field(["clock"])?.string("displayValue").map { " \($0)" } ?? ""
            let code = (detail.field(["team"])?.string("id")).flatMap { abbr[$0] }.map { " (\($0))" } ?? ""
            let og = detail.bool("ownGoal") == true ? " (OG)" : ""
            let pen = detail.bool("penaltyKick") == true ? " (P)" : ""
            out.append("\(player)\(time)\(og)\(pen)\(code)")
        }
        return out
    }

    // MARK: Summary (announced added time)

    /// Announced added time per half from the summary feed's `commentary`, e.g.
    /// "Fourth official has announced 6 minutes of added time." stamped at "45'"
    /// (first half) or "90'" (second). Returns the minutes for each half.
    static func announcedAddedTime(_ summary: JSONValue) -> (firstHalf: Int?, secondHalf: Int?) {
        var firstHalf: Int?
        var secondHalf: Int?
        for entry in summary.field(["commentary"])?.arrayValue ?? [] {
            guard let text = entry.string("text"),
                  text.lowercased().contains("added time"),
                  let minutes = firstInt(in: text) else { continue }
            let stamp = entry.field(["time"])?.string("displayValue") ?? ""
            switch Int(stamp.prefix(while: { $0.isNumber })) {
            case 90: secondHalf = minutes
            case 45: firstHalf = minutes
            default: break
            }
        }
        return (firstHalf, secondHalf)
    }

    /// First run of digits in a string ("…announced 6 minutes…" → 6).
    private static func firstInt(in text: String) -> Int? {
        var digits = ""
        for ch in text {
            if ch.isNumber { digits.append(ch) }
            else if !digits.isEmpty { break }
        }
        return Int(digits)
    }

    // MARK: Standings (teams + groups)

    static func groups(_ json: JSONValue) -> [TournamentGroup] {
        parseGroups(json).map { letter, rows in
            TournamentGroup(id: letter, name: letter, teamIds: rows.map(\.id), inlineTeams: rows)
        }
    }

    static func teams(_ json: JSONValue) -> [Team] {
        parseGroups(json).flatMap(\.rows).sorted { $0.name < $1.name }
    }

    /// `children[].standings.entries[]` → [(group letter, ranked rows)], sorted by letter.
    private static func parseGroups(_ json: JSONValue) -> [(letter: String, rows: [Team])] {
        (json.field(["children"])?.arrayValue ?? []).compactMap { child in
            guard let rawName = child.string("name") else { return nil }
            let letter = rawName.replacingOccurrences(of: "Group ", with: "").trimmingCharacters(in: .whitespaces)
            let entries = child.field(["standings"])?.field(["entries"])?.arrayValue ?? []
            var rows = entries.compactMap { entry -> Team? in
                guard let team = entry.field(["team"]) else { return nil }
                let name = team.string("displayName", "name") ?? ""
                let id = team.string("id") ?? name
                guard !id.isEmpty || !name.isEmpty else { return nil }
                let code = (team.string("abbreviation") ?? FlagBook.code(forName: name) ?? String(name.prefix(3))).uppercased()
                let stats = ESPNStats(entry.field(["stats"])?.arrayValue ?? [])
                return Team(
                    id: id,
                    name: name.isEmpty ? code : name,
                    namePersian: nil,
                    code: code,
                    groupName: letter,
                    flagURL: FlagBook.flagCDNURL(code: code, name: name),
                    played: stats["gamesPlayed"], wins: stats["wins"], draws: stats["ties"], losses: stats["losses"],
                    goalsFor: stats["pointsFor"], goalsAgainst: stats["pointsAgainst"], points: stats["points"]
                )
            }
            // FIFA group ordering: points, then goal difference, then goals scored.
            rows.sort {
                ($0.points ?? 0, ($0.goalsFor ?? 0) - ($0.goalsAgainst ?? 0), $0.goalsFor ?? 0)
                    > ($1.points ?? 0, ($1.goalsFor ?? 0) - ($1.goalsAgainst ?? 0), $1.goalsFor ?? 0)
            }
            return (letter, rows)
        }
        .sorted { $0.letter < $1.letter }
    }

    /// Reads ESPN `stats: [{ name, value }]` by stat name (values arrive as doubles).
    private struct ESPNStats {
        private let byName: [String: Int]
        init(_ array: [JSONValue]) {
            var map: [String: Int] = [:]
            for stat in array {
                if let name = stat.string("name"), let value = stat.int("value") { map[name] = value }
            }
            byName = map
        }
        subscript(_ name: String) -> Int? { byName[name] }
    }
}

/// Client for ESPN's (unofficial) site API for the FIFA World Cup. Free, no auth.
/// Same actor pattern as the other clients: per-resource cache + in-flight
/// coalescing so the store's four concurrent resource calls share downloads.
///
/// `baseURL` is the league root, e.g.
/// `https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world`.
/// Matches come from `<base>/scoreboard`; group standings live under the sibling
/// `apis/v2/...` path (not `apis/site/v2`), derived here.
actor ESPNAPIClient: TournamentDataSource {
    private let scoreboardURL: URL
    private let standingsURL: URL
    private let summaryBase: URL
    private let session: URLSession
    private var cache: [String: (at: Date, json: JSONValue)] = [:]
    private var inflight: [String: Task<JSONValue, Error>] = [:]
    private let ttl: TimeInterval = 8

    /// Bracket the whole WC2026 window so one scoreboard call returns every match
    /// (finished, live, and upcoming) in a single request.
    private static let dateRange = "20260601-20260731"

    init(baseURL: URL) {
        var board = URLComponents(url: baseURL.appendingPathComponent("scoreboard"), resolvingAgainstBaseURL: false)
        board?.queryItems = [
            URLQueryItem(name: "dates", value: Self.dateRange),
            URLQueryItem(name: "limit", value: "1000"),
        ]
        self.scoreboardURL = board?.url ?? baseURL.appendingPathComponent("scoreboard")

        // Standings sit under apis/v2 (not apis/site/v2).
        var root = baseURL.absoluteString
        if root.hasSuffix("/") { root.removeLast() }
        let standingsRoot = root.replacingOccurrences(of: "/apis/site/v2/", with: "/apis/v2/")
        var standings = URLComponents(string: standingsRoot + "/standings")
        standings?.queryItems = [URLQueryItem(name: "season", value: "2026")]
        self.standingsURL = standings?.url ?? URL(string: standingsRoot + "/standings")!

        // Per-match details (announced added time lives here, not on the scoreboard).
        self.summaryBase = baseURL.appendingPathComponent("summary")

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: TournamentDataSource

    func matches() async throws -> [Match] {
        var matches = ESPNParser.matches(try await get(scoreboardURL, key: "scoreboard"), fetchedAt: Date())
        // The announced added time ("+6") is only in each match's summary feed, not
        // the scoreboard — fetch it just for matches actually in stoppage right now.
        for i in matches.indices where matches[i].stoppagePlus != nil && !matches[i].isHalftime {
            guard let summary = try? await get(summaryURL(eventId: matches[i].id), key: "summary-\(matches[i].id)")
            else { continue }
            let added = ESPNParser.announcedAddedTime(summary)
            matches[i].announcedAddedTime = (matches[i].minute ?? 0) >= 90 ? added.secondHalf : added.firstHalf
        }
        return matches
    }

    private func summaryURL(eventId: String) -> URL {
        var c = URLComponents(url: summaryBase, resolvingAgainstBaseURL: false)
        c?.queryItems = [URLQueryItem(name: "event", value: eventId)]
        return c?.url ?? summaryBase
    }

    /// Standings power both the team list and the group tables. A failure here is
    /// non-fatal — the store copes with empty teams/groups and falls back to the
    /// names carried on each match.
    func teams() async throws -> [Team] {
        guard let json = try? await get(standingsURL, key: "standings") else { return [] }
        return ESPNParser.teams(json)
    }

    func groups() async throws -> [TournamentGroup] {
        guard let json = try? await get(standingsURL, key: "standings") else { return [] }
        return ESPNParser.groups(json)
    }

    /// No venue endpoint — the store derives stadiums from match `venueName`.
    func stadiums() async throws -> [Stadium] { [] }

    // MARK: Transport (cache + coalescing)

    private func get(_ url: URL, key: String) async throws -> JSONValue {
        if let hit = cache[key], Date().timeIntervalSince(hit.at) < ttl { return hit.json }
        if let task = inflight[key] { return try await task.value }

        let task = Task { try await self.fetch(url) }
        inflight[key] = task
        defer { inflight[key] = nil }
        let json = try await task.value
        cache[key] = (Date(), json)
        return json
    }

    private func fetch(_ url: URL) async throws -> JSONValue {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw APIError(message: "HTTP \(http.statusCode)", isNotFound: http.statusCode == 404)
        }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
}
