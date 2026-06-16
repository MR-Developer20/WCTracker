import Foundation

/// Self-contained sample data for Demo mode — a fully-populated, "live" France v
/// Senegal match so the whole UI (scoreboard, pitch, goals, stats, stadium,
/// weather) can be tested without any network or a real live match.
enum DemoData {
    static let homeTeamId = "FRA"
    static let awayTeamId = "SEN"
    static let homeColorHex = "2A4FB8"
    static let awayColorHex = "0E8A3D"

    // MARK: Scoreboard match — cycles through every clock state for testing

    /// A point in the demo timeline. The store advances through these so the
    /// scoreboard exercises 1st half, both halves' added time, half time, 2nd half
    /// and full time — matching the WorldCup26Widget scorebug behaviour.
    struct Scene {
        var minute: Int            // 0 when finished
        var isHalftime: Bool
        var stoppagePlus: Int?
        var announcedAddedTime: Int?
        var finished: Bool
        var label: String
    }

    static let scenes: [Scene] = [
        Scene(minute: 30, isHalftime: false, stoppagePlus: nil, announcedAddedTime: nil, finished: false, label: "1st half"),
        Scene(minute: 45, isHalftime: false, stoppagePlus: 2, announcedAddedTime: 2, finished: false, label: "1st-half added time"),
        Scene(minute: 45, isHalftime: true, stoppagePlus: nil, announcedAddedTime: nil, finished: false, label: "Half time"),
        Scene(minute: 75, isHalftime: false, stoppagePlus: nil, announcedAddedTime: nil, finished: false, label: "2nd half"),
        Scene(minute: 90, isHalftime: false, stoppagePlus: 5, announcedAddedTime: 6, finished: false, label: "2nd-half added time"),
        Scene(minute: 0, isHalftime: false, stoppagePlus: nil, announcedAddedTime: nil, finished: true, label: "Full time"),
    ]

    /// Build the demo match for a scene. `sceneStart` anchors a live, ticking clock
    /// (elapsed = scene.minute + time since the scene began).
    static func match(scene: Scene, sceneStart: Date) -> Match {
        var m = Match(
            id: "demo-live",
            homeTeamId: homeTeamId, awayTeamId: awayTeamId,
            homeName: "France", awayName: "Senegal",
            homeScore: 2, awayScore: 1,
            date: sceneStart.addingTimeInterval(-Double(scene.minute) * 60), stadiumId: nil,
            finishedFlag: scene.finished, statusText: scene.finished ? "finished" : "live",
            scorers: ["Mbappé 23' (FRA)", "Griezmann 61' (FRA)", "I. Sarr 78' (SEN)"],
            minute: scene.finished ? nil : scene.minute, venueName: "MetLife Stadium")
        m.homeColorHex = homeColorHex
        m.awayColorHex = awayColorHex
        // Real ESPN country-flag images so the demo scoreboard matches live.
        m.homeLogoURL = URL(string: "https://a.espncdn.com/i/teamlogos/countries/500/fra.png")
        m.awayLogoURL = URL(string: "https://a.espncdn.com/i/teamlogos/countries/500/sen.png")
        m.fetchedAt = scene.minute > 0 ? sceneStart : nil
        m.isHalftime = scene.isHalftime
        m.stoppagePlus = scene.stoppagePlus
        m.announcedAddedTime = scene.announcedAddedTime
        // Broadcast-style minute string, so the "match minute" clock toggle has data
        // in demo mode too ("30'", "45'+2'", "90'+5'").
        if !scene.finished && scene.minute > 0 {
            m.displayClock = scene.stoppagePlus.map { "\(scene.minute)'+\($0)'" } ?? "\(scene.minute)'"
        }
        return m
    }

    // MARK: Full match detail (lineups, events, goals, stats, venue)

    static func detail() -> MatchDetail {
        MatchDetail(
            eventId: "demo-live",
            homeLineup: homeLineup,
            awayLineup: awayLineup,
            events: events,
            goals: goals,
            stats: stats,
            venue: VenueInfo(name: "MetLife Stadium", city: "East Rutherford",
                             country: "USA", attendance: 82_500))
    }

    static func weather() -> MatchWeather {
        MatchWeather(temperatureC: 24, condition: "Partly Cloudy",
                     symbolName: "cloud.sun.fill", windKph: 12, humidity: 55,
                     source: .openMeteo)
    }

    // MARK: Lineups (4-3-3 each)

    private static let homeLineup = Lineup(
        teamId: homeTeamId, name: "France", code: "FRA", colorHex: homeColorHex,
        formation: "4-3-3", isHome: true,
        starters: PitchLayout.place([
            raw("16", "Maignan", "G", headshot: 159382),
            raw("2", "Koundé", "RB", headshot: 184221), raw("17", "Saliba", "CD-R", headshot: 188160),
            raw("4", "Upamecano", "CD-L", headshot: 202501), raw("22", "T. Hernández", "LB", headshot: 213248),
            raw("8", "Tchouaméni", "DM", headshot: 213718), raw("7", "Griezmann", "CM-R", headshot: 216617),
            raw("6", "Camavinga", "CM-L", headshot: 219627),
            raw("11", "Dembélé", "RW", headshot: 222776), raw("10", "Mbappé", "F", headshot: 228619), raw("20", "Barcola", "LW", headshot: 230626),
        ], isHome: true, formation: "4-3-3"),
        substitutes: [])

    private static let awayLineup = Lineup(
        teamId: awayTeamId, name: "Senegal", code: "SEN", colorHex: awayColorHex,
        formation: "4-3-3", isHome: false,
        starters: PitchLayout.place([
            raw("16", "E. Mendy", "G", headshot: 231059),
            raw("22", "Sabaly", "RB", headshot: 236721), raw("3", "Koulibaly", "CD-R", headshot: 236890),
            raw("21", "A. Diallo", "CD-L", headshot: 238016), raw("12", "Jakobs", "LB", headshot: 238033),
            raw("6", "N. Mendy", "DM", headshot: 238712), raw("5", "Gueye", "CM-R", headshot: 239350),
            raw("17", "P. Sarr", "CM-L", headshot: 240965),
            raw("18", "I. Sarr", "RW", headshot: 241627), raw("9", "Dia", "F", subbedOut: true, headshot: 248276), raw("10", "Mané", "LW", headshot: 249524),
        ], isHome: false, formation: "4-3-3"),
        substitutes: [])

    private static func raw(_ number: String, _ name: String, _ abbr: String,
                            subbedOut: Bool = false, headshot: Int? = nil) -> PitchLayout.RawPlayer {
        // shortName "X. Lastname" → keep as given; id from number+name. Demo players
        // carry sample per-position stats so the tap-a-player card is populated in
        // demo mode just like it is from the live feed. ESPN has no headshots for
        // these specific players, so the demo uses real (unrelated) ESPN soccer
        // headshots purely to populate the headshot feature.
        PitchLayout.RawPlayer(id: "\(name)-\(number)", name: name, shortName: name,
                              number: number, abbr: abbr,
                              headshotURL: headshot.flatMap { URL(string: "https://a.espncdn.com/i/headshots/soccer/players/full/\($0).png") },
                              subbedOut: subbedOut,
                              stats: sampleStats(number: number, abbr: abbr, name: name))
    }

    /// Plausible, position-specific match stats seeded by the jersey number so each
    /// player differs deterministically. Known demo scorers get a goal so the card
    /// agrees with the goals list. Labels are unique per player (PlayerStat.id = label).
    private static let demoScorers: Set<String> = ["Mbappé", "Griezmann", "I. Sarr"]

    private static func sampleStats(number: String, abbr: String, name: String) -> [PlayerStat] {
        let n = Int(number) ?? 9
        // deterministic spread in 0...span from the jersey number
        func r(_ base: Int, _ span: Int) -> Int { base + (n * 17 + 7) % (span + 1) }
        func s(_ name: String, _ label: String, _ value: Int) -> PlayerStat {
            PlayerStat(label: label, name: name, value: "\(value)")
        }
        let rating = PlayerStat(label: "RAT", name: "Rating",
                                value: String(format: "%.1f", 6.4 + Double((n * 13) % 26) / 10.0))
        let minutes = s("Minutes", "MIN", 90)

        if abbr == "G" {
            return [s("Saves", "SV", r(2, 4)), s("Goals Conceded", "GC", r(0, 2)),
                    s("Passes", "PAS", r(20, 18)),
                    PlayerStat(label: "PA%", name: "Pass Accuracy", value: "\(r(76, 18))%"),
                    minutes, rating]
        }

        let scored = demoScorers.contains(name)
        let isDef = abbr.hasSuffix("B") || abbr.hasPrefix("CD")
        let isFwd = abbr == "F" || abbr == "RW" || abbr == "LW"
        let goals = s("Goals", "G", scored ? 1 : (isFwd ? r(0, 1) : 0))

        if isDef {
            return [s("Tackles", "TKL", r(1, 4)), s("Interceptions", "INT", r(0, 3)),
                    s("Clearances", "CLR", r(1, 5)), s("Passes", "PAS", r(40, 35)),
                    PlayerStat(label: "PA%", name: "Pass Accuracy", value: "\(r(82, 14))%"),
                    goals, minutes, rating]
        }
        if isFwd {
            return [goals, s("Shots", "SH", r(1, 4)), s("Shots on Target", "SOT", r(0, 3)),
                    s("Key Passes", "KP", r(0, 3)), s("Touches", "TCH", r(28, 30)),
                    minutes, rating]
        }
        // midfield
        return [goals, s("Passes", "PAS", r(45, 40)),
                PlayerStat(label: "PA%", name: "Pass Accuracy", value: "\(r(80, 16))%"),
                s("Key Passes", "KP", r(0, 3)), s("Tackles", "TKL", r(1, 4)),
                s("Duels Won", "DW", r(3, 8)), minutes, rating]
    }

    // MARK: Goals + events

    private static let goals: [GoalEvent] = [
        GoalEvent(minute: 23, clockText: "23'", scorer: "Kylian Mbappé", assist: "Antoine Griezmann", isHome: true, isOwnGoal: false, isPenalty: false),
        GoalEvent(minute: 61, clockText: "61'", scorer: "Antoine Griezmann", assist: "Ousmane Dembélé", isHome: true, isOwnGoal: false, isPenalty: false),
        GoalEvent(minute: 78, clockText: "78'", scorer: "Ismaïla Sarr", assist: nil, isHome: false, isOwnGoal: false, isPenalty: true),
    ]

    private static let events: [MatchEvent] = [
        ev(0, "Kickoff", "", nil, nil, false),
        ev(23, "Goal", "Goal! France 1, Senegal 0. Kylian Mbappé scores.", "FRA", "Kylian Mbappé", true, scoring: true),
        ev(34, "Yellow Card", "Idrissa Gueye is shown the yellow card.", "SEN", "Idrissa Gueye", false),
        ev(45, "Halftime", "First half ends, France 1, Senegal 0.", nil, nil, false),
        ev(61, "Goal", "Goal! France 2, Senegal 0. Antoine Griezmann scores.", "FRA", "Antoine Griezmann", true, scoring: true),
        ev(70, "Substitution", "Substitution, Senegal. Nicolas Jackson replaces Boulaye Dia.", "SEN", nil, false),
        ev(78, "Goal", "Penalty Goal! France 2, Senegal 1. Ismaïla Sarr converts the penalty.", "SEN", "Ismaïla Sarr", false, scoring: true),
        ev(82, "Yellow Card", "Aurélien Tchouaméni is shown the yellow card.", "FRA", "Aurélien Tchouaméni", true),
    ]

    private static func ev(_ minute: Int, _ type: String, _ text: String, _ teamCode: String?, _ player: String?, _ isHome: Bool, scoring: Bool = false) -> MatchEvent {
        MatchEvent(minute: minute, clockText: minute == 0 ? "" : "\(minute)'",
                   typeText: type, detailText: nil, scoringPlay: scoring,
                   teamId: teamCode, isHome: teamCode == nil ? nil : isHome,
                   playerName: player, assistName: nil, text: text)
    }

    // MARK: Team stats

    private static let stats: [TeamStat] = [
        stat("Possession", "58%", "42%", 58, 42, true),
        stat("Shots", "14", "9", 14, 9, false),
        stat("Shots on Target", "5", "3", 5, 3, false),
        stat("Corners", "6", "4", 6, 4, false),
        stat("Fouls", "10", "12", 10, 12, false),
        stat("Offsides", "2", "1", 2, 1, false),
        stat("Saves", "2", "4", 2, 4, false),
        stat("Accurate Passes", "486", "352", 486, 352, false),
        stat("Yellow Cards", "1", "2", 1, 2, false),
    ]

    private static func stat(_ label: String, _ h: String, _ a: String, _ hv: Double, _ av: Double, _ pct: Bool) -> TeamStat {
        TeamStat(label: label, homeText: h, awayText: a, homeValue: hv, awayValue: av, isPercent: pct)
    }

    // MARK: Ball waypoints (cycled by the demo ticker for visible movement)

    static let ballWaypoints: [PitchPoint] = [
        PitchPoint(x: 0.50, y: 0.50),
        PitchPoint(x: 0.66, y: 0.34),
        PitchPoint(x: 0.80, y: 0.46),
        PitchPoint(x: 0.90, y: 0.55),  // France attacking the right goal
        PitchPoint(x: 0.72, y: 0.66),
        PitchPoint(x: 0.50, y: 0.58),
        PitchPoint(x: 0.34, y: 0.42),
        PitchPoint(x: 0.18, y: 0.50),  // Senegal attacking the left goal
        PitchPoint(x: 0.30, y: 0.62),
        PitchPoint(x: 0.48, y: 0.46),
    ]
}
