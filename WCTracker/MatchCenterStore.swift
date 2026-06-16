import Foundation
import Combine
import SwiftUI

/// Drives the second screen: which match is in focus, its detail (lineups/events/
/// stats/venue), venue weather, and the 2026 match replay mode.
@MainActor
final class MatchCenterStore: ObservableObject {
    enum Mode: String { case live, replay }

    let tournament: TournamentStore

    // Live mode
    @Published var mode: Mode = .live
    @Published var selectedMatchID: String? { didSet { refreshFocus(dataChanged: true) } }
    /// The match currently shown in live mode (nil = no live match → placeholder).
    @Published private(set) var liveFocus: Match?
    @Published private(set) var detail: MatchDetail?
    @Published private(set) var weather: MatchWeather?
    @Published private(set) var isLoadingDetail = false

    // Demo mode — a self-contained sample match for testing (no network).
    @Published var demoMode: Bool {
        didSet {
            UserDefaults.standard.set(demoMode, forKey: "demoMode")
            applyDemoChange()
        }
    }
    @Published private(set) var demoBall: PitchPoint = .center
    private var demoTimer: Timer?
    private var demoWaypoint = 0
    private var demoSceneIndex = 0
    private var demoSceneStart = Date()
    private let demoSceneDuration: TimeInterval = 8

    /// Current demo scene name (shown on the DEMO chip).
    var demoSceneLabel: String { DemoData.scenes[demoSceneIndex].label }

    @Published var weatherSource: WeatherSource {
        didSet {
            UserDefaults.standard.set(weatherSource.rawValue, forKey: "weatherSource")
            Task { await reloadWeather() }
        }
    }

    /// The app's full-screen background color, stored as a 6-digit hex string.
    @Published var backgroundColorHex: String {
        didSet { UserDefaults.standard.set(backgroundColorHex, forKey: "backgroundColorHex") }
    }

    /// The resolved background color (defaults to black if the stored hex is malformed).
    var backgroundColor: Color { Color(hex: backgroundColorHex) ?? .black }

    // Replay mode — step through a finished 2026 match's real event timeline (ESPN).
    @Published private(set) var replayMatches: [Match] = []
    @Published private(set) var selectedReplayMatch: Match?
    @Published private(set) var replayDetail: MatchDetail?
    @Published var replayIndex: Int = 0
    @Published var isPlaying = false
    @Published private(set) var isLoadingReplay = false

    private let summary = MatchSummaryService()
    private let weatherService = MatchWeatherService()

    private var detailTimer: Timer?
    private var replayTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var loadedFocusID: String?
    private var loadedWeatherCity: String?
    private var loadedWeatherSource: WeatherSource?
    private var started = false

    // Live focus resolution: keep showing a match for a grace window after it ends,
    // then fall back to the placeholder.
    private var previouslyLiveIDs: Set<String> = []
    private var recentlyEndedID: String?
    private var recentlyEndedAt: Date?
    private let endGrace: TimeInterval = 120   // keep a finished match on screen for 2 minutes
    private var focusTimer: Timer?

    init(tournament: TournamentStore) {
        self.tournament = tournament
        let stored = UserDefaults.standard.string(forKey: "weatherSource").flatMap(WeatherSource.init(rawValue:))
        self.weatherSource = stored ?? .weatherKit
        self.backgroundColorHex = UserDefaults.standard.string(forKey: "backgroundColorHex") ?? "000000"
        self.demoMode = UserDefaults.standard.bool(forKey: "demoMode")
            || CommandLine.arguments.contains("--demo")
    }

    func start() {
        guard !started else { return }
        started = true
        // React to scoreboard updates (a new live match, score changes, an end, etc.).
        tournament.$matches
            .receive(on: RunLoop.main)
            .sink { [weak self] matches in
                self?.refreshReplayMatches(matches)
                self?.refreshFocus(dataChanged: true)
            }
            .store(in: &cancellables)

        // Refresh the focused match's detail (score/events/stats) periodically.
        detailTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.reloadFocus(force: true) }
        }
        // Re-resolve focus often so the post-match grace window expires promptly.
        focusTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshFocus(dataChanged: false) }
        }
        if demoMode { startDemoTicker() }
        refreshFocus(dataChanged: true)
    }

    // MARK: Focus match

    var focusMatch: Match? {
        if demoMode { return DemoData.match(scene: DemoData.scenes[demoSceneIndex], sceneStart: demoSceneStart) }
        return liveFocus
    }

    /// What the live screen should show: a manually-picked match, else the live
    /// match, else a match that ended within the last 2 minutes, else nil (which
    /// makes the screen show the "no match live" placeholder).
    private func resolveLiveFocus() -> Match? {
        let matches = tournament.matches
        if let id = selectedMatchID, let m = matches.first(where: { $0.id == id }) { return m }
        if let live = tournament.liveMatches.first { return live }
        if let endedID = recentlyEndedID, let endedAt = recentlyEndedAt,
           Date().timeIntervalSince(endedAt) < endGrace,
           let m = matches.first(where: { $0.id == endedID }) {
            return m
        }
        return nil
    }

    /// Recompute the live focus, tracking matches that just ended so they linger for
    /// the grace window. Triggers a detail fetch when the focused match changes.
    private func refreshFocus(dataChanged: Bool) {
        // Record any match that went live → finished since the last check.
        let liveNow = Set(tournament.liveMatches.map(\.id))
        for endedID in previouslyLiveIDs.subtracting(liveNow) {
            recentlyEndedID = endedID
            recentlyEndedAt = Date()
        }
        previouslyLiveIDs = liveNow

        let resolved = resolveLiveFocus()
        if resolved?.id != liveFocus?.id {
            liveFocus = resolved
            loadedFocusID = nil
            if resolved == nil {
                detail = nil; weather = nil
                loadedWeatherCity = nil; loadedWeatherSource = nil
            } else {
                Task { await reloadFocus(force: true) }
            }
        } else if dataChanged {
            liveFocus = resolved   // refresh the focused match's score/clock in place
        }
    }

    /// What the live UI should render — demo data when demo mode is on, else the
    /// fetched detail / weather / event-estimated ball.
    var activeDetail: MatchDetail? { demoMode ? DemoData.detail() : detail }
    var activeWeather: MatchWeather? { demoMode ? DemoData.weather() : weather }
    var ball: PitchPoint? {
        if demoMode { return demoBall }
        guard let events = detail?.events else { return nil }
        let idx = events.lastIndex(where: { $0.isHome != nil })
        return BallEstimator.target(events: events, lastIndex: idx)
    }

    /// Teams change ends for the 2nd half and the 2nd half of extra time.
    static func endsSwitched(atMinute minute: Int) -> Bool {
        switch minute {
        case 46...90, 106...120: return true
        default: return false
        }
    }

    /// Whether the live pitch is mirrored (home defending the right goal).
    var liveFlipped: Bool {
        guard let m = focusMatch else { return false }
        let minute: Int
        if let mn = m.minute, mn > 0 { minute = mn }
        else if m.finishedFlag { minute = 90 }
        // Kickoff-anchored sources (demo) report no minute; cap at 90 so 2nd-half
        // added time (elapsed > 90) still counts as the second half, not extra time.
        else { minute = min(Int((m.elapsed() ?? 0) / 60), 90) }
        return Self.endsSwitched(atMinute: minute)
    }

    /// Whether the replay pitch is mirrored — follows the current event's minute,
    /// so the teams switch ends as the replay crosses halftime.
    var replayFlipped: Bool {
        Self.endsSwitched(atMinute: currentReplayEvent?.minute ?? 0)
    }

    private func reloadFocus(force: Bool) async {
        if demoMode { return }
        guard mode == .live, let match = focusMatch else { return }
        let changed = match.id != loadedFocusID
        guard force || changed else { return }
        loadedFocusID = match.id
        if changed { detail = nil; weather = nil; loadedWeatherCity = nil }

        isLoadingDetail = true
        defer { isLoadingDetail = false }
        if let d = try? await summary.detail(eventId: match.id,
                                             homeTeamId: match.homeTeamId,
                                             awayTeamId: match.awayTeamId, force: force) {
            // Ignore a late response for a match the user already switched away from.
            guard match.id == focusMatch?.id else { return }
            detail = d
            await reloadWeather()
        }
    }

    private func reloadWeather() async {
        guard let venue = detail?.venue, let city = venue.geocodeQuery else { return }
        // Skip a redundant fetch only when the venue and the *requested* source are
        // both unchanged and we already have a reading (a WeatherKit→Open-Meteo
        // fallback still counts as "loaded" for the requested source).
        let upToDate = city == loadedWeatherCity && loadedWeatherSource == weatherSource && weather != nil
        if upToDate { return }
        loadedWeatherCity = city
        loadedWeatherSource = weatherSource
        if let w = await weatherService.weather(for: venue, source: weatherSource) {
            weather = w
        }
    }

    // MARK: Mode switching

    func setMode(_ newMode: Mode) {
        mode = newMode
        if newMode == .replay {
            stopReplayTimer(); isPlaying = false
            stopDemoTicker()
            refreshReplayMatches(tournament.matches)
        } else {
            stopReplayTimer(); isPlaying = false
            if demoMode { startDemoTicker() } else { refreshFocus(dataChanged: true) }
        }
    }

    // MARK: Demo mode

    private func applyDemoChange() {
        if demoMode {
            mode = .live
            stopReplayTimer(); isPlaying = false
            startDemoTicker()
        } else {
            stopDemoTicker()
            loadedFocusID = nil   // force a fresh fetch for the real focus match
            refreshFocus(dataChanged: true)
        }
    }

    private func startDemoTicker() {
        demoWaypoint = 0
        demoSceneIndex = 0
        demoSceneStart = Date()
        demoBall = DemoData.ballWaypoints.first ?? .center
        demoTimer?.invalidate()
        demoTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.demoWaypoint = (self.demoWaypoint + 1) % DemoData.ballWaypoints.count
                self.demoBall = DemoData.ballWaypoints[self.demoWaypoint]
                // Advance to the next clock-state scene every few seconds, looping.
                if Date().timeIntervalSince(self.demoSceneStart) >= self.demoSceneDuration {
                    self.demoSceneIndex = (self.demoSceneIndex + 1) % DemoData.scenes.count
                    self.demoSceneStart = Date()
                }
            }
        }
    }

    private func stopDemoTicker() {
        demoTimer?.invalidate()
        demoTimer = nil
    }

    // MARK: Replay (2026 matches only)

    /// Finished 2026 World Cup matches (they have full event timelines), newest first.
    private func refreshReplayMatches(_ matches: [Match]) {
        let now = Date()
        replayMatches = matches
            .filter { $0.phase(now: now) == .finished }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// The playback steps — the selected match's real event timeline.
    var replayEvents: [MatchEvent] { replayDetail?.events ?? [] }

    var currentReplayEvent: MatchEvent? {
        guard replayEvents.indices.contains(replayIndex) else { return nil }
        return replayEvents[replayIndex]
    }

    /// Estimated ball position for the events shown so far (no free 2026 positional feed).
    var replayBall: PitchPoint? {
        let shown = Array(replayEvents.prefix(replayIndex + 1))
        guard !shown.isEmpty else { return nil }
        let idx = shown.lastIndex(where: { $0.isHome != nil })
        return BallEstimator.target(events: shown, lastIndex: idx)
    }

    func selectReplay(_ match: Match) async {
        isLoadingReplay = true
        defer { isLoadingReplay = false }
        stopReplayTimer(); isPlaying = false; replayIndex = 0
        selectedReplayMatch = match
        replayDetail = nil
        if let d = try? await summary.detail(eventId: match.id,
                                             homeTeamId: match.homeTeamId,
                                             awayTeamId: match.awayTeamId, force: true) {
            guard selectedReplayMatch?.id == match.id else { return }
            replayDetail = d
            replayIndex = 0
            if !replayEvents.isEmpty { playReplay() }
        }
    }

    func playReplay() {
        guard !replayEvents.isEmpty else { return }
        isPlaying = true
        stopReplayTimer()
        replayTimer = Timer.scheduledTimer(withTimeInterval: 1.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.replayIndex < self.replayEvents.count - 1 {
                    self.replayIndex += 1
                } else {
                    self.pauseReplay()
                }
            }
        }
    }

    func pauseReplay() {
        isPlaying = false
        stopReplayTimer()
    }

    func toggleReplay() { isPlaying ? pauseReplay() : playReplay() }

    private func stopReplayTimer() {
        replayTimer?.invalidate()
        replayTimer = nil
    }
}
