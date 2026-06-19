import CarPlay
import SwiftUI
import UIKit

/// The single CarPlay screen: the scoreboard for the current live match — a rasterized
/// copy of the app's scoreboard shown in a `CPListImageRowItem` (CarPlay's largest image
/// slot), with a few headline team stats below it. It's a list template (not a tab bar)
/// since it's the only screen, and `updateSections(_:)` refreshes it in place so the
/// 1-second clock tick never rebuilds the screen. CarPlay owns the actual layout/sizing
/// per head unit. Always follows the current live match, independent of whatever the phone
/// has manually selected.
@MainActor
final class CarPlayInterface {

    /// The root (and only) template — the scoreboard list.
    let rootTemplate = CPListTemplate(title: "Live Match", sections: [])

    /// Display scale of the car screen, set by the scene delegate on connect so the
    /// rasterized scoreboard is crisp on the head unit. Falls back to a sane default.
    var imageScale: CGFloat = 2

    // Re-rendering the tiles every clock tick is wasteful when nothing visible changed,
    // so cache them keyed on the values that drive the scoreboard.
    private var cachedScoreboardSignature: String?
    private var cachedScoreboardImages: [UIImage]?

    // MARK: Refresh

    /// Rebuild the scoreboard from the current live match. Cheap enough to run on a
    /// 1-second cadence so the clock ticks.
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
        // Mirror the phone: synthesized MM:SS by default, ESPN's broadcast minute when
        // the user prefers it — so the CarPlay clock reads like the app's scoreboard.
        let clock = clockText(match, half: half, broadcast: env.center.useBroadcastClock)

        rootTemplate.updateSections(scoreboardSections(match: match, home: home, away: away,
                                                       detail: detail, clock: clock,
                                                       badge: env.center.badgeImage))
    }

    private func showNoLiveMatch() {
        rootTemplate.updateSections([CPListSection(items: [
            CPListItem(text: "No live match", detailText: "Check back near kickoff.")
        ])])
    }

    private func scoreboardSections(match: Match, home: Team, away: Team,
                                    detail: MatchDetail?, clock: String,
                                    badge: UIImage?) -> [CPListSection] {
        let upcoming = match.phase() == .upcoming
        let homeScore = upcoming ? nil : match.homeScore
        let awayScore = upcoming ? nil : match.awayScore

        // The headline row is a CPListImageRowItem (CarPlay's largest image slot, ~95 pt
        // per image) carrying the scoreboard split into three tiles — home, badge+clock,
        // away — so each renders big across the row. The status sits above as the row's
        // title. If rendering ever fails, fall back to a plain text row so the score reads.
        let tiles = scoreboardImages(home: home, away: away,
                                     homeScore: homeScore, awayScore: awayScore,
                                     clock: clock, badge: badge)
        let scoreRow: any CPListTemplateItem
        if let tiles {
            scoreRow = CPListImageRowItem(text: statusLine(match), images: tiles)
        } else {
            scoreRow = CPListItem(
                text: "\(home.flag) \(home.code)  \(homeScore.map(String.init) ?? "–") – \(awayScore.map(String.init) ?? "–")  \(away.code) \(away.flag)",
                detailText: statusLine(match))
        }
        let clockItem = CPListItem(text: clock, detailText: "Clock")

        var sections = [CPListSection(items: [scoreRow, clockItem])]
        // A couple of headline stats so "scoreboard + team stats" reads on the
        // narrowest head unit (the small-screen priority).
        let headline = (detail?.stats ?? []).prefix(4).map { statRow($0) }
        if !headline.isEmpty {
            sections.append(CPListSection(items: Array(headline), header: "Team Stats",
                                          sectionIndexTitle: nil))
        }
        return sections
    }

    private func statRow(_ stat: TeamStat) -> CPListItem {
        CPListItem(text: stat.label, detailText: "\(stat.homeText)   –   \(stat.awayText)")
    }

    /// Rasterize the three scoreboard tiles (home, badge+clock, away) for the image row.
    /// Cached on the values that change them so the per-second tick only re-renders when
    /// needed. Returns nil if any tile fails to render (caller falls back to text).
    private func scoreboardImages(home: Team, away: Team,
                                  homeScore: Int?, awayScore: Int?,
                                  clock: String, badge: UIImage?) -> [UIImage]? {
        let signature = [home.code, away.code,
                         homeScore.map(String.init) ?? "-", awayScore.map(String.init) ?? "-",
                         clock, badge == nil ? "0" : "1"].joined(separator: "|")
        if signature == cachedScoreboardSignature, let cached = cachedScoreboardImages {
            return cached
        }

        let homeTile = CarPlayTeamTile(flag: home.flag, code: home.code,
                                       kit: Color.kit(for: home), score: homeScore)
        let centerTile = CarPlayCenterTile(badge: badge, clock: clock)
        let awayTile = CarPlayTeamTile(flag: away.flag, code: away.code,
                                       kit: Color.kit(for: away), score: awayScore)
        guard let h = render(homeTile), let c = render(centerTile), let a = render(awayTile) else {
            return nil
        }

        let images = [h, c, a]
        cachedScoreboardSignature = signature
        cachedScoreboardImages = images
        return images
    }

    /// Rasterize one tile view at the car screen's scale. `.alwaysOriginal` so CarPlay
    /// shows the full-color tile instead of tinting it.
    private func render(_ view: some View) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = imageScale
        renderer.isOpaque = false
        return renderer.uiImage?.withRenderingMode(.alwaysOriginal)
    }

    // MARK: Clock / status formatting (mirrors BroadcastScoreboard.clockText)

    private func clockText(_ match: Match, half: Int, broadcast: Bool) -> String {
        switch match.phase() {
        case .finished:
            return "FT"
        case .upcoming:
            guard let d = match.date else { return "—" }
            let df = DateFormatter()
            df.dateFormat = Calendar.current.isDate(d, inSameDayAs: Date()) ? "HH:mm" : "MMM d"
            return df.string(from: d)
        case .live:
            if match.isHalftime { return "HT" }
            if broadcast {
                // ESPN's exact broadcast minute, incl. "+N" added time, when present.
                if let dc = match.displayClock, !dc.isEmpty { return dc }
                if let elapsed = match.elapsed() { return "\(max(1, Int(elapsed / 60) + 1))'" }
                return "LIVE"
            }
            // Default: synthesized MM:SS, held at the period boundary during added time
            // so it reads "45:00" / "90:00" — exactly like the app's main clock chip.
            guard let elapsed = match.elapsed() else { return "LIVE" }
            let capped = stoppageBoundary(match, half: half).map { min(elapsed, Double($0 * 60)) } ?? elapsed
            return String(format: "%02d:%02d", Int(capped) / 60, Int(capped) % 60)
        }
    }

    /// The minute the clock holds at while the feed reports added time — the current
    /// period's end (half, full time, or an extra-time half). nil during ordinary play.
    /// Ported from `BroadcastScoreboard.stoppageBoundary`.
    private func stoppageBoundary(_ match: Match, half: Int) -> Int? {
        let regulationEnd = half * 2
        let ends = [half, regulationEnd, regulationEnd + 15, regulationEnd + 30]
        guard let minute = match.minute, minute > 0 else {
            return match.stoppagePlus != nil ? regulationEnd : nil
        }
        guard match.stoppagePlus != nil else { return nil }
        return ends.last(where: { minute >= $0 })
    }

    private func statusLine(_ match: Match) -> String {
        switch match.phase() {
        case .upcoming: return match.statusText ?? "Upcoming"
        case .live: return match.isHalftime ? "Half Time" : "Live"
        case .finished: return "Full Time"
        }
    }
}
