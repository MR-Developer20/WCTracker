import CarPlay
import UIKit

/// Recreates the scoreboard, team stats and pitch (lineups) for the live match
/// using only CarPlay-allowed elements: a tab bar over list templates. CarPlay owns
/// the actual layout/sizing per head unit, so the content adapts to the car's screen
/// automatically. Always follows the current live match, independent of whatever the
/// phone has manually selected.
///
/// List templates are used throughout (rather than `CPInformationTemplate`) because
/// `CPListTemplate.updateSections(_:)` refreshes content in place — so the 1-second
/// clock tick never rebuilds the tab bar or resets the driver's selected tab.
@MainActor
final class CarPlayInterface {

    /// Tab 1 — broadcast scoreboard: score + clock, then a few headline stats so the
    /// small-screen priority (scoreboard + team stats) reads on one screen.
    private let scoreboard = CPListTemplate(title: "Match", sections: [])
    /// Tab 2 — full team-stats comparison (home vs away rows).
    private let stats = CPListTemplate(title: "Team Stats", sections: [])
    /// Tab 3 — the pitch recreated as both starting XIs grouped by formation line.
    private let lineups = CPListTemplate(title: "Lineups", sections: [])

    private(set) lazy var rootTemplate: CPTabBarTemplate = {
        scoreboard.tabTitle = "Score"
        scoreboard.tabImage = UIImage(systemName: "soccerball")
        stats.tabTitle = "Stats"
        stats.tabImage = UIImage(systemName: "chart.bar.fill")
        lineups.tabTitle = "Pitch"
        lineups.tabImage = UIImage(systemName: "person.3.fill")
        return CPTabBarTemplate(templates: [scoreboard, stats, lineups])
    }()

    // MARK: Refresh

    /// Rebuild every tab's contents from the current live match. Cheap enough to run
    /// on a 1-second cadence so the clock ticks.
    func update(env: AppEnvironment) {
        guard let match = env.tournament.liveMatches.first else {
            showNoLiveMatch()
            return
        }
        let home = env.tournament.team(for: match, home: true)
        let away = env.tournament.team(for: match, home: false)
        // Use the shared detail only when it's actually this (live) match — keeps
        // CarPlay on the live game even if the phone manually picked another.
        let detail = env.center.activeDetail.flatMap { $0.eventId == match.id ? $0 : nil }
        let half = detail?.format?.halfMinutes ?? 45

        scoreboard.updateSections(scoreboardSections(match: match, home: home, away: away,
                                                     detail: detail, half: half))
        stats.updateSections(statsSections(home: home, away: away, detail: detail))
        lineups.updateSections(lineupSections(home: home, away: away, detail: detail))
    }

    private func showNoLiveMatch() {
        // Fresh instances per tab — CarPlay list items/sections shouldn't be shared
        // across templates.
        func placeholder() -> [CPListSection] {
            [CPListSection(items: [
                CPListItem(text: "No live match", detailText: "Check back near kickoff.")
            ])]
        }
        scoreboard.updateSections(placeholder())
        stats.updateSections(placeholder())
        lineups.updateSections(placeholder())
    }

    private func scoreboardSections(match: Match, home: Team, away: Team,
                                    detail: MatchDetail?, half: Int) -> [CPListSection] {
        let score = CPListItem(
            text: "\(home.flag) \(home.code)  \(match.homeScore) – \(match.awayScore)  \(away.code) \(away.flag)",
            detailText: statusLine(match))
        let clock = CPListItem(text: clockText(match, half: half), detailText: "Clock")

        var sections = [CPListSection(items: [score, clock])]
        // A couple of headline stats so "scoreboard + team stats" reads on the
        // narrowest head unit (the small-screen priority).
        let headline = (detail?.stats ?? []).prefix(4).map { statRow($0) }
        if !headline.isEmpty {
            sections.append(CPListSection(items: Array(headline), header: "Team Stats",
                                          sectionIndexTitle: nil))
        }
        return sections
    }

    private func statsSections(home: Team, away: Team, detail: MatchDetail?) -> [CPListSection] {
        let teamStats = detail?.stats ?? []
        guard !teamStats.isEmpty else {
            return [CPListSection(items: [
                CPListItem(text: "Stats unavailable",
                           detailText: "Team stats appear once the match is underway.")
            ])]
        }
        return [CPListSection(items: teamStats.map { statRow($0) },
                              header: "\(home.code)  vs  \(away.code)",
                              sectionIndexTitle: nil)]
    }

    private func statRow(_ stat: TeamStat) -> CPListItem {
        CPListItem(text: stat.label, detailText: "\(stat.homeText)   –   \(stat.awayText)")
    }

    private func lineupSections(home: Team, away: Team, detail: MatchDetail?) -> [CPListSection] {
        guard let detail, detail.hasLineups else {
            return [CPListSection(items: [
                CPListItem(text: "Lineups not available", detailText: "They appear near kickoff.")
            ])]
        }
        var sections: [CPListSection] = []
        if let l = detail.homeLineup { sections.append(section(for: l, team: home)) }
        if let l = detail.awayLineup { sections.append(section(for: l, team: away)) }
        return sections
    }

    private func section(for lineup: Lineup, team: Team) -> CPListSection {
        // Starters arrive already ordered by formation line (PitchLayout.place).
        let items = lineup.starters.map { p -> CPListItem in
            var detail = p.positionAbbr
            if p.subbedOut { detail += " · subbed off" }
            return CPListItem(text: "#\(p.number)  \(p.shortName)", detailText: detail)
        }
        let header = [team.code, lineup.formation].compactMap { $0 }.joined(separator: " · ")
        return CPListSection(items: items, header: header, sectionIndexTitle: nil)
    }

    // MARK: Clock / status formatting (mirrors BroadcastScoreboard.clockText)

    private func clockText(_ match: Match, half: Int) -> String {
        switch match.phase() {
        case .finished:
            return "FT"
        case .upcoming:
            guard let d = match.date else { return "—" }
            let df = DateFormatter()
            df.dateFormat = Calendar.current.isDate(d, inSameDayAs: Date()) ? "HH:mm" : "MMM d, HH:mm"
            return df.string(from: d)
        case .live:
            if match.isHalftime { return "HT" }
            // ESPN's exact broadcast minute (includes "+N" added time) when present.
            if let dc = match.displayClock, !dc.isEmpty { return dc }
            if let elapsed = match.elapsed() { return "\(max(1, Int(elapsed / 60) + 1))'" }
            return "LIVE"
        }
    }

    private func statusLine(_ match: Match) -> String {
        switch match.phase() {
        case .upcoming: return match.statusText ?? "Upcoming"
        case .live: return match.isHalftime ? "Half Time" : "Live"
        case .finished: return "Full Time"
        }
    }
}
