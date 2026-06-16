import Foundation

// MARK: - Tolerant JSON value
// The worldcup26 API returns numbers as strings ("home_score": "0") and booleans
// as "TRUE"/"FALSE", and field names are not guaranteed. Everything decodes
// through this enum and is extracted with forgiving key/type lookups.

enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value"))
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .number(let n): return Int(n)
        case .string(let s): return Int(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let b): return b
        case .number(let n): return n != 0
        case .string(let s):
            switch s.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        default: return nil
        }
    }

    var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    private static func normalize(_ key: String) -> String {
        key.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
    }

    /// Case/underscore-insensitive lookup trying several candidate keys in order.
    func field(_ keys: [String]) -> JSONValue? {
        guard case .object(let dict) = self else { return nil }
        for key in keys {
            let target = Self.normalize(key)
            if let hit = dict.first(where: { Self.normalize($0.key) == target }) {
                if case .null = hit.value { continue }
                return hit.value
            }
        }
        return nil
    }

    func string(_ keys: String...) -> String? { field(keys)?.stringValue }
    func int(_ keys: String...) -> Int? { field(keys)?.intValue }
    func bool(_ keys: String...) -> Bool? { field(keys)?.boolValue }
}

// MARK: - Domain models

struct Team: Identifiable {
    var id: String
    var name: String
    var namePersian: String?
    var code: String
    var groupName: String?
    var flagURL: URL?
    var played: Int?
    var wins: Int?
    var draws: Int?
    var losses: Int?
    var goalsFor: Int?
    var goalsAgainst: Int?
    var points: Int?
    /// ISO 3166-1 alpha-2 code when the API provides one — most reliable flag source.
    var iso2: String? = nil
    /// Primary kit color as a hex string (e.g. "FF8200"), from the live feed.
    var colorHex: String? = nil

    var flag: String {
        if let iso2, let emoji = FlagBook.emojiFlag(iso: iso2) { return emoji }
        return FlagBook.flag(code: code, name: name)
    }

    static func from(_ json: JSONValue) -> Team? {
        guard case .object = json else { return nil }
        // Standings rows nest identity under "team" while stats sit on the row:
        // { "rank": 1, "team": {id, name, fifaCode, iso2}, "played": 0, "points": 0 }
        let identity = json.field(["team"]).flatMap { v -> JSONValue? in
            if case .object = v { return v }
            return nil
        } ?? json

        let name = identity.string("name_en", "english_name", "name", "title", "team_name", "country") ?? ""
        let id = identity.string("id", "team_id", "_id") ?? name
        guard !id.isEmpty || !name.isEmpty else { return nil }
        let code = identity.string("code", "fifa_code", "short_name", "abbr", "tla")
            ?? FlagBook.code(forName: name)
            ?? String(name.prefix(3)).uppercased()
        let persian = identity.string("name_fa", "persian_name", "fa_name")
            ?? identity.field(["name_i18n", "names"])?.string("fa")
        return Team(
            id: id,
            name: name.isEmpty ? code : name,
            namePersian: persian,
            code: code.uppercased(),
            groupName: json.string("group", "group_name", "group_letter", "group_id"),
            flagURL: identity.string("flag", "flag_url", "image", "logo").flatMap { URL(string: $0) },
            played: json.int("played", "p", "matches_played", "games_played"),
            wins: json.int("wins", "w", "win", "won"),
            draws: json.int("draws", "d", "draw", "drawn"),
            losses: json.int("losses", "l", "lose", "lost"),
            goalsFor: json.int("goals_for", "gf", "scored", "goals_scored"),
            goalsAgainst: json.int("goals_against", "ga", "conceded"),
            points: json.int("points", "pts", "point"),
            iso2: identity.string("iso2", "iso", "country_code")
        )
    }
}

struct TournamentGroup: Identifiable {
    var id: String
    var name: String
    var teamIds: [String]
    var inlineTeams: [Team]

    static func from(_ json: JSONValue) -> TournamentGroup? {
        guard case .object = json else { return nil }
        let name = json.string("name", "group_name", "letter", "group", "title") ?? ""
        let id = json.string("id", "group_id", "_id") ?? name
        guard !id.isEmpty || !name.isEmpty else { return nil }
        var teamIds: [String] = []
        var inline: [Team] = []
        if let arr = json.field(["teams", "team_list", "members", "standings"])?.arrayValue {
            for item in arr {
                if case .object = item, let t = Team.from(item) {
                    inline.append(t)
                    teamIds.append(t.id)
                } else if let s = item.stringValue {
                    teamIds.append(s)
                }
            }
        }
        return TournamentGroup(id: id, name: name.isEmpty ? id : name, teamIds: teamIds, inlineTeams: inline)
    }
}

struct Match: Identifiable {
    enum Phase { case upcoming, live, finished }

    var id: String
    var homeTeamId: String
    var awayTeamId: String
    var homeName: String?
    var awayName: String?
    var homeScore: Int
    var awayScore: Int
    var date: Date?
    var stadiumId: String?
    var finishedFlag: Bool
    var statusText: String?
    var scorers: [String]
    /// Football minute reported by a live feed (0 = not started / unknown).
    var minute: Int? = nil
    /// When the live feed reported `minute` — anchors a smoothly ticking clock.
    var fetchedAt: Date? = nil
    /// Venue as a plain name (live feed has no stadium ids).
    var venueName: String? = nil
    /// Running stoppage minute parsed from the feed clock ("90'+3'" → 3); ticks up
    /// during added time. Used to detect that the match is in stoppage.
    var stoppagePlus: Int? = nil
    /// Added time the fourth official *announced* for the current half (e.g. 6),
    /// from the summary feed's commentary — the static "+N" board, distinct from
    /// the running `stoppagePlus`. nil until announced / fetched.
    var announcedAddedTime: Int? = nil
    /// The feed reports the match as in-progress but paused for the interval
    /// (ESPN `STATUS_HALFTIME`). The clock holds at "HT" instead of ticking,
    /// since the feed freezes the minute at 45 for the whole break.
    var isHalftime: Bool = false
    /// Primary kit colors (hex) for the two teams, from the live feed — used for
    /// the accent dots, since the standings endpoint omits team colors.
    var homeColorHex: String? = nil
    var awayColorHex: String? = nil
    /// Team flag/crest image URLs from the live feed (ESPN `team.logo`).
    var homeLogoURL: URL? = nil
    var awayLogoURL: URL? = nil

    /// Live = kicked off, not flagged finished, and within a 135-minute window
    /// so stale data can't keep a "live" match on screen forever.
    func phase(now: Date = Date()) -> Phase {
        if finishedFlag { return .finished }

        let normalizedStatus = statusText?.lowercased()
        if let st = normalizedStatus,
           st.contains("finish") || st.contains("ended") || st == "ft" || st.contains("full") {
            return .finished
        }

        // A live feed that reports a running minute is authoritative, but expire
        // it if the feed stops updating (anchor + 135min cap).
        if let minute, minute > 0 {
            if let fetchedAt {
                let total = Double(minute) * 60 + now.timeIntervalSince(fetchedAt)
                return total < 135 * 60 ? .live : .finished
            }
            return .live
        }

        // A feed that explicitly says "live" beats kickoff-time inference (the
        // kickoff may be stale if the match was delayed) — but a feed stuck on
        // "live" long past kickoff still expires.
        if let st = normalizedStatus,
           st.contains("live") || st.contains("progress") || st.contains("playing") {
            if let d = date, now >= d.addingTimeInterval(135 * 60) { return .finished }
            return .live
        }

        guard let d = date else { return .upcoming }
        if now < d { return .upcoming }
        if now < d.addingTimeInterval(135 * 60) { return .live }
        return .finished
    }

    func elapsed(now: Date = Date()) -> TimeInterval? {
        // Anchor on the feed-reported minute when available so the clock matches
        // the broadcast clock, ticking forward from the moment we fetched it.
        if let minute, minute > 0 {
            return Double(minute) * 60 + (fetchedAt.map { now.timeIntervalSince($0) } ?? 0)
        }
        guard let d = date, now >= d else { return nil }
        return now.timeIntervalSince(d)
    }

    static let dateFormats = ["MM/dd/yyyy HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mmXXXXX", "dd/MM/yyyy HH:mm", "yyyy/MM/dd HH:mm"]

    static func parseDate(_ raw: String) -> Date? {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        for format in dateFormats {
            df.dateFormat = format
            if let d = df.date(from: raw) { return d }
        }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: raw)
    }

    /// Combine split fields like date "2026-06-11" + time "13:00 UTC-6".
    static func parseDate(dateString: String, timeString: String?) -> Date? {
        guard let timeString, dateString.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            return parseDate(dateString)
        }
        var time = timeString.trimmingCharacters(in: .whitespaces)
        var timeZone = TimeZone.current
        if let utcRange = time.range(of: #"UTC[+-]?\d{1,2}(:\d{2})?"#, options: .regularExpression) {
            let offsetPart = String(time[utcRange].dropFirst(3))
            time.removeSubrange(utcRange)
            time = time.trimmingCharacters(in: .whitespaces)
            let pieces = offsetPart.split(separator: ":")
            if let hours = Int(pieces.first ?? "") {
                let minutes = pieces.count > 1 ? (Int(pieces[1]) ?? 0) : 0
                let sign = hours < 0 ? -1 : 1
                timeZone = TimeZone(secondsFromGMT: hours * 3600 + sign * minutes * 60) ?? .current
            }
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = timeZone
        df.dateFormat = "yyyy-MM-dd HH:mm"
        return df.date(from: "\(dateString) \(time)") ?? parseDate(dateString)
    }

    /// Parse a score as a [home, away] array, "1-0"/"1 – 0" string, or
    /// {home, away} object.
    static func parseScore(_ value: JSONValue?) -> (home: Int, away: Int)? {
        guard let value else { return nil }
        if let arr = value.arrayValue, arr.count == 2, let h = arr[0].intValue, let a = arr[1].intValue {
            return (h, a)
        }
        if case .object = value, let h = value.int("home", "home_score", "h"), let a = value.int("away", "away_score", "a") {
            return (h, a)
        }
        if let s = value.stringValue {
            let parts = s.components(separatedBy: CharacterSet(charactersIn: "-–:")).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, let h = Int(parts[0]), let a = Int(parts[1]) {
                return (h, a)
            }
        }
        return nil
    }

    static func scorerList(_ json: JSONValue) -> [String] {
        var scorers: [String] = []
        if let arr = json.field(["scorers", "goals", "goal_scorers", "events"])?.arrayValue {
            for item in arr {
                if let s = item.stringValue {
                    scorers.append(s)
                } else if case .object = item {
                    let player = item.string("player", "name", "scorer") ?? "?"
                    let minute = item.string("minute", "time", "min").map { " \($0)'" } ?? ""
                    let team = item.string("team", "team_code").map { " (\($0))" } ?? ""
                    scorers.append("\(player)\(minute)\(team)")
                }
            }
        }
        return scorers
    }

    static func from(_ json: JSONValue) -> Match? {
        guard case .object = json else { return nil }
        let id = json.string("id", "match_id", "game_id", "_id") ?? UUID().uuidString

        // Plain-string team refs (live feed sends names: "home": "Mexico").
        func teamRef(_ keys: [String]) -> (id: String, name: String?) {
            guard let v = json.field(keys) else { return ("", nil) }
            if case .object = v {
                return (v.string("id", "team_id", "_id") ?? "", v.string("name_en", "name", "title"))
            }
            let s = v.stringValue ?? ""
            return (s, s.isEmpty || Int(s) != nil ? nil : s)
        }

        let home = teamRef(["home_team_id", "home_team", "home_id", "home", "team1_id", "team1"])
        let away = teamRef(["away_team_id", "away_team", "away_id", "away", "team2_id", "team2"])

        // live_data (when present) carries the in-play detail.
        let liveData = json.field(["live_data", "live", "in_play"])

        var scorers = scorerList(json)
        if scorers.isEmpty, let liveData {
            scorers = scorerList(liveData)
        }

        var homeScore = json.int("home_score", "home_goals", "score1") ?? 0
        var awayScore = json.int("away_score", "away_goals", "score2") ?? 0
        if let score = parseScore(json.field(["score", "result", "ft_score"]))
            ?? liveData.flatMap({ parseScore($0.field(["score", "result"])) }) {
            homeScore = score.home
            awayScore = score.away
        }

        var minute = json.int("minute", "live_minute", "elapsed", "current_minute", "match_minute", "time_elapsed")
        if minute == nil || minute == 0 {
            minute = liveData?.int("minute", "elapsed") ?? minute
        }

        // A unix timestamp (wcup2026 "datetime") is authoritative; otherwise fall
        // back to a date string (optionally combined with a separate time field).
        let date: Date?
        if let unix = json.field(["datetime", "timestamp", "unix", "kickoff_ts"])?.intValue, unix > 1_000_000_000 {
            date = Date(timeIntervalSince1970: TimeInterval(unix))
        } else {
            let dateString = json.string("local_date", "date", "datetime", "kickoff", "kickoff_utc", "match_date", "utc_date")
            date = dateString.flatMap { parseDate(dateString: $0, timeString: json.string("time", "kickoff_time", "local_time")) }
                ?? json.string("time").flatMap(parseDate)
        }

        // venue may be a plain string or an object: {"id": "...", "name": "Estadio Azteca"}
        var stadiumId = json.string("stadium_id", "stadium", "venue_id")
        var venueName = json.string("venue", "ground", "city", "location")
        if let venueObject = json.field(["venue", "stadium"]), case .object = venueObject {
            stadiumId = venueObject.string("id") ?? stadiumId
            venueName = venueObject.string("name") ?? venueName
        }

        return Match(
            id: id,
            homeTeamId: home.id,
            awayTeamId: away.id,
            homeName: home.name,
            awayName: away.name,
            homeScore: homeScore,
            awayScore: awayScore,
            date: date,
            stadiumId: stadiumId,
            finishedFlag: json.bool("finished", "is_finished", "completed", "ended", "played") ?? false,
            statusText: json.string("status", "state", "match_status"),
            scorers: scorers,
            minute: minute,
            venueName: venueName
        )
    }
}

struct Stadium: Identifiable {
    var id: String
    var name: String
    var city: String?
    var country: String?
    var capacity: Int?

    static func from(_ json: JSONValue) -> Stadium? {
        guard case .object = json else { return nil }
        let name = json.string("name_en", "name", "stadium_name", "title") ?? ""
        let id = json.string("id", "stadium_id", "_id") ?? name
        guard !name.isEmpty || !id.isEmpty else { return nil }
        return Stadium(
            id: id,
            name: name.isEmpty ? id : name,
            city: json.string("city", "city_en", "location"),
            country: json.string("country", "country_en", "nation"),
            capacity: json.int("capacity", "seats")
        )
    }
}

// MARK: - Flags

enum FlagBook {
    private static let special: [String: String] = [
        "ENG": "🏴󠁧󠁢󠁥󠁮󠁧󠁿", "SCO": "🏴󠁧󠁢󠁳󠁣󠁴󠁿", "WAL": "🏴󠁧󠁢󠁷󠁬󠁳󠁿",
    ]

    private static let fifaToISO: [String: String] = [
        "USA": "US", "MEX": "MX", "CAN": "CA", "FRA": "FR", "SEN": "SN", "BRA": "BR",
        "ARG": "AR", "GER": "DE", "DEU": "DE", "ESP": "ES", "POR": "PT", "NED": "NL",
        "BEL": "BE", "CRO": "HR", "ITA": "IT", "SUI": "CH", "AUT": "AT", "POL": "PL",
        "DEN": "DK", "SWE": "SE", "NOR": "NO", "SRB": "RS", "UKR": "UA", "TUR": "TR",
        "CZE": "CZ", "SVK": "SK", "SVN": "SI", "ROU": "RO", "HUN": "HU", "GRE": "GR",
        "ALB": "AL", "MAR": "MA", "TUN": "TN", "ALG": "DZ", "EGY": "EG", "NGA": "NG",
        "GHA": "GH", "CIV": "CI", "CMR": "CM", "RSA": "ZA", "MLI": "ML", "BFA": "BF",
        "CPV": "CV", "COD": "CD", "GAB": "GA", "BIH": "BA", "JPN": "JP", "KOR": "KR", "PRK": "KP",
        "KSA": "SA", "IRN": "IR", "IRQ": "IQ", "QAT": "QA", "UAE": "AE", "UZB": "UZ",
        "JOR": "JO", "AUS": "AU", "NZL": "NZ", "IDN": "ID", "CRC": "CR", "PAN": "PA",
        "HON": "HN", "JAM": "JM", "HAI": "HT", "CUW": "CW", "GUA": "GT", "SLV": "SV",
        "ECU": "EC", "COL": "CO", "PER": "PE", "CHI": "CL", "URU": "UY", "PAR": "PY",
        "BOL": "BO", "VEN": "VE", "IRL": "IE", "ISL": "IS", "FIN": "FI", "RUS": "RU",
    ]

    private static let nameToCode: [String: String] = [
        "france": "FRA", "senegal": "SEN", "united states": "USA", "usa": "USA",
        "mexico": "MEX", "canada": "CAN", "brazil": "BRA", "argentina": "ARG",
        "germany": "GER", "spain": "ESP", "portugal": "POR", "netherlands": "NED",
        "belgium": "BEL", "croatia": "CRO", "italy": "ITA", "switzerland": "SUI",
        "austria": "AUT", "poland": "POL", "denmark": "DEN", "sweden": "SWE",
        "norway": "NOR", "serbia": "SRB", "ukraine": "UKR", "turkey": "TUR",
        "morocco": "MAR", "tunisia": "TUN", "algeria": "ALG", "egypt": "EGY",
        "nigeria": "NGA", "ghana": "GHA", "ivory coast": "CIV", "cote d'ivoire": "CIV",
        "cameroon": "CMR", "south africa": "RSA", "cape verde": "CPV", "mali": "MLI",
        "japan": "JPN", "south korea": "KOR", "korea republic": "KOR",
        "saudi arabia": "KSA", "iran": "IRN", "qatar": "QAT", "uzbekistan": "UZB",
        "jordan": "JOR", "australia": "AUS", "new zealand": "NZL", "indonesia": "IDN",
        "costa rica": "CRC", "panama": "PAN", "honduras": "HON", "jamaica": "JAM",
        "haiti": "HAI", "curacao": "CUW", "curaçao": "CUW", "ecuador": "ECU",
        "colombia": "COL", "peru": "PER", "chile": "CHI", "uruguay": "URU",
        "paraguay": "PAR", "england": "ENG", "scotland": "SCO", "wales": "WAL",
        "ireland": "IRL", "iceland": "ISL", "czech republic": "CZE", "czechia": "CZE",
        "bosnia & herzegovina": "BIH", "bosnia and herzegovina": "BIH", "bosnia": "BIH",
        "slovakia": "SVK", "slovenia": "SVN", "romania": "ROU", "hungary": "HUN",
        "greece": "GRE", "albania": "ALB", "finland": "FIN", "venezuela": "VEN",
        "bolivia": "BOL", "united arab emirates": "UAE", "burkina faso": "BFA",
        "dr congo": "COD", "congo dr": "COD", "gabon": "GAB",
    ]

    static func code(forName name: String) -> String? {
        nameToCode[name.lowercased().trimmingCharacters(in: .whitespaces)]
    }

    /// Regional-indicator emoji from an ISO 3166-1 alpha-2 code.
    static func emojiFlag(iso: String) -> String? {
        let upper = iso.uppercased()
        guard upper.count == 2 else { return nil }
        var out = ""
        for scalar in upper.unicodeScalars {
            guard scalar.value >= UnicodeScalar("A").value, scalar.value <= UnicodeScalar("Z").value,
                  let flagScalar = Unicode.Scalar(0x1F1E6 + scalar.value - UnicodeScalar("A").value) else { return nil }
            out.unicodeScalars.append(flagScalar)
        }
        return out
    }

    static func flag(code: String, name: String) -> String {
        let fifa = code.uppercased()
        if let s = special[fifa] { return s }
        var iso = fifaToISO[fifa]
        if iso == nil, let derived = self.code(forName: name) {
            if let s = special[derived] { return s }
            iso = fifaToISO[derived]
        }
        if iso == nil, fifa.count == 2 { iso = fifa }
        return iso.flatMap { emojiFlag(iso: $0) } ?? "🏳️"
    }

    /// flagcdn.com image for a FIFA code — covers the home-nations codes that
    /// have no plain ISO flag (gb-eng / gb-sct / gb-wls).
    static func flagCDNURL(code: String, name: String = "") -> URL? {
        let fifa = code.uppercased()
        let homeNations = ["ENG": "gb-eng", "SCO": "gb-sct", "WAL": "gb-wls"]
        var slug = homeNations[fifa] ?? fifaToISO[fifa]?.lowercased()
        if slug == nil, let derived = self.code(forName: name) {
            slug = homeNations[derived] ?? fifaToISO[derived]?.lowercased()
        }
        guard let slug else { return nil }
        return URL(string: "https://flagcdn.com/w80/\(slug).png")
    }
}
