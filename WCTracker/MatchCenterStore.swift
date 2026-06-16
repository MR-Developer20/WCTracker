import Foundation
import Combine
import SwiftUI
import UIKit

/// Drives the second screen: which match is in focus, its detail (lineups/events/
/// stats/venue), venue weather, and the 2026 match replay mode.
@MainActor
final class MatchCenterStore: ObservableObject {
    enum Mode: String { case live, replay, standings }

    let tournament: TournamentStore

    /// iCloud key-value store — syncs the card layout (order + visibility) and the
    /// badge/ball images across the user's devices. Everything is also mirrored to
    /// local storage so it still works when the iCloud capability is unavailable.
    private let cloud = NSUbiquitousKeyValueStore.default
    private var applyingCloudChange = false
    private enum CloudKey {
        static let cardOrder = "cardOrder"
        static let hiddenCards = "hiddenCards"
        static let badge = "badgeImageData"
        static let ball = "ballImageData"
        static let backgroundColor = "backgroundColorHex"
        static let clock = "useBroadcastClock"
    }

    // Live mode
    @Published var mode: Mode = .live
    @Published var showHeatMap = false   // possession heat-map overlay (live + replay)
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

    /// Temperature unit for the weather card (°C / °F).
    @Published var temperatureUnit: TemperatureUnit {
        didSet { UserDefaults.standard.set(temperatureUnit.rawValue, forKey: "temperatureUnit") }
    }

    /// Show ESPN's exact broadcast minute ("37'", "45'+2'") instead of the synthesized
    /// running MM:SS clock. The feed's time is minute-granular, so this is guaranteed to
    /// match the broadcast; off by default to keep the running-clock scorebug look.
    /// Synced via iCloud, mirrored locally.
    @Published var useBroadcastClock: Bool {
        didSet {
            guard !applyingCloudChange else { return }
            cloud.set(useBroadcastClock, forKey: CloudKey.clock)
            cloud.synchronize()
            UserDefaults.standard.set(useBroadcastClock, forKey: CloudKey.clock)
        }
    }

    /// The app's full-screen background color, stored as a 6-digit hex string.
    /// Synced via iCloud, mirrored locally.
    @Published var backgroundColorHex: String {
        didSet {
            guard !applyingCloudChange else { return }
            cloud.set(backgroundColorHex, forKey: CloudKey.backgroundColor)
            cloud.synchronize()
            UserDefaults.standard.set(backgroundColorHex, forKey: CloudKey.backgroundColor)
        }
    }

    /// The resolved background color (defaults to black if the stored hex is malformed).
    var backgroundColor: Color { Color(hex: backgroundColorHex) ?? .black }

    /// User-customizable order and visibility of the right-panel info cards.
    @Published var cardOrder: [InfoCardKind] { didSet { persistCards() } }
    @Published var hiddenCards: Set<InfoCardKind> { didSet { persistCards() } }

    /// The cards to actually render, in order, excluding hidden ones.
    var visibleCards: [InfoCardKind] { cardOrder.filter { !hiddenCards.contains($0) } }

    func moveCards(from: IndexSet, to: Int) { cardOrder.move(fromOffsets: from, toOffset: to) }

    func setCard(_ card: InfoCardKind, visible: Bool) {
        if visible { hiddenCards.remove(card) } else { hiddenCards.insert(card) }
    }

    private func persistCards() {
        guard !applyingCloudChange else { return }  // don't echo a cloud-driven change back
        let order = cardOrder.map(\.rawValue)
        let hidden = hiddenCards.map(\.rawValue)
        cloud.set(order, forKey: CloudKey.cardOrder)
        cloud.set(hidden, forKey: CloudKey.hiddenCards)
        cloud.synchronize()
        // Local mirror (used when iCloud is unavailable).
        UserDefaults.standard.set(order, forKey: CloudKey.cardOrder)
        UserDefaults.standard.set(hidden, forKey: CloudKey.hiddenCards)
    }

    /// User-supplied tournament badge for the scoreboard. The app ships with no
    /// emblem (the official mark is trademarked); the user provides their own image,
    /// stored locally. nil falls back to a neutral trophy symbol.
    @Published private(set) var badgeImage: UIImage?

    /// User-supplied ball image for the pitch. nil falls back to a soccerball symbol.
    @Published private(set) var ballImage: UIImage?

    private func imageFileURL(_ name: String) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    /// Persist an image to iCloud (downscaled to stay within the key-value store's
    /// budget) and to a local file mirror used when iCloud is unavailable.
    private func storeImage(_ image: UIImage, cloudKey: String, fileName: String) {
        if let data = Self.downscaledPNG(image, maxDimension: 256) {
            cloud.set(data, forKey: cloudKey)
            cloud.synchronize()
        }
        if let full = image.pngData() { try? full.write(to: imageFileURL(fileName)) }
    }

    private func removeImage(cloudKey: String, fileName: String) {
        cloud.removeObject(forKey: cloudKey)
        cloud.synchronize()
        try? FileManager.default.removeItem(at: imageFileURL(fileName))
    }

    /// Load a stored image, preferring iCloud and falling back to the local mirror.
    private func loadImage(cloudKey: String, fileName: String) -> UIImage? {
        if let data = cloud.data(forKey: cloudKey), let image = UIImage(data: data) { return image }
        return UIImage(contentsOfFile: imageFileURL(fileName).path)
    }

    /// Downscale so the longest side is at most `maxDimension`, keeping alpha, so the
    /// badge/ball images fit comfortably inside iCloud's ~1 MB key-value quota.
    private static func downscaledPNG(_ image: UIImage, maxDimension: CGFloat) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.pngData()
    }

    /// Save a user-chosen badge image (from the picker) and show it.
    func setBadge(data: Data) {
        guard let image = UIImage(data: data) else { return }
        badgeImage = image
        storeImage(image, cloudKey: CloudKey.badge, fileName: "badge.png")
    }

    /// Remove the user's badge, reverting to the neutral fallback.
    func clearBadge() {
        badgeImage = nil
        removeImage(cloudKey: CloudKey.badge, fileName: "badge.png")
    }

    /// Save a user-chosen ball image and show it.
    func setBall(data: Data) {
        guard let image = UIImage(data: data) else { return }
        ballImage = image
        storeImage(image, cloudKey: CloudKey.ball, fileName: "ball.png")
    }

    /// Remove the user's ball image, reverting to the soccerball symbol.
    func clearBall() {
        ballImage = nil
        removeImage(cloudKey: CloudKey.ball, fileName: "ball.png")
    }

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

    // Live focus resolution: after the shown match turns .finished, keep it on screen
    // for a grace window, then fall back to the placeholder.
    private var graceCandidateID: String?   // the match being shown (lingers when it ends)
    private var graceFinishedAt: Date?      // when that match was first observed .finished
    private let endGrace: TimeInterval = 120   // keep a finished match on screen for 2 minutes
    private var focusTimer: Timer?

    init(tournament: TournamentStore) {
        self.tournament = tournament
        // Pull the latest iCloud values into the in-memory cache before reading them
        // below, so a freshly-opened app shows what was last synced from other devices.
        cloud.synchronize()
        let stored = UserDefaults.standard.string(forKey: "weatherSource").flatMap(WeatherSource.init(rawValue:))
        self.weatherSource = stored ?? .weatherKit
        self.backgroundColorHex = cloud.string(forKey: CloudKey.backgroundColor)
            ?? UserDefaults.standard.string(forKey: CloudKey.backgroundColor) ?? "000000"
        self.temperatureUnit = UserDefaults.standard.string(forKey: "temperatureUnit")
            .flatMap(TemperatureUnit.init(rawValue:)) ?? .celsius
        self.useBroadcastClock = (cloud.object(forKey: CloudKey.clock) != nil)
            ? cloud.bool(forKey: CloudKey.clock)
            : UserDefaults.standard.bool(forKey: CloudKey.clock)
        self.demoMode = UserDefaults.standard.bool(forKey: "demoMode")
            || CommandLine.arguments.contains("--demo")
        // Card order: saved order (iCloud first, then the local mirror), with any
        // newly-added card kinds appended.
        let savedRaw = (cloud.array(forKey: CloudKey.cardOrder) as? [String])
            ?? (UserDefaults.standard.array(forKey: CloudKey.cardOrder) as? [String])
        let saved = savedRaw?.compactMap(InfoCardKind.init(rawValue:)) ?? []
        self.cardOrder = saved + InfoCardKind.allCases.filter { !saved.contains($0) }
        let hiddenRaw = (cloud.array(forKey: CloudKey.hiddenCards) as? [String])
            ?? (UserDefaults.standard.array(forKey: CloudKey.hiddenCards) as? [String])
        self.hiddenCards = Set(hiddenRaw?.compactMap(InfoCardKind.init(rawValue:)) ?? [])
        // Badge/ball images: iCloud first, local mirror as fallback. (loadImage is an
        // instance method, so call it only after all stored properties above are set.)
        self.badgeImage = loadImage(cloudKey: CloudKey.badge, fileName: "badge.png")
        self.ballImage = loadImage(cloudKey: CloudKey.ball, fileName: "ball.png")
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

        // Refresh the focused match's detail (events/stats/lineups) about as fast as
        // ESPN updates it.
        detailTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.reloadFocus(force: true) }
        }
        // Re-resolve focus often so the post-match grace window expires promptly.
        focusTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshFocus(dataChanged: false) }
        }
        if demoMode { startDemoTicker() }
        startCloudSync()
        refreshFocus(dataChanged: true)
    }

    // MARK: iCloud sync (card layout + badge/ball images)

    private func startCloudSync() {
        // Push any existing local-only settings up the first time we run with iCloud,
        // then watch for changes made on the user's other devices.
        if cloud.array(forKey: CloudKey.cardOrder) == nil { persistCards() }
        if cloud.string(forKey: CloudKey.backgroundColor) == nil {
            cloud.set(backgroundColorHex, forKey: CloudKey.backgroundColor)
        }
        if cloud.object(forKey: CloudKey.clock) == nil {
            cloud.set(useBroadcastClock, forKey: CloudKey.clock)
        }
        if cloud.data(forKey: CloudKey.badge) == nil, let b = badgeImage {
            storeImage(b, cloudKey: CloudKey.badge, fileName: "badge.png")
        }
        if cloud.data(forKey: CloudKey.ball) == nil, let b = ballImage {
            storeImage(b, cloudKey: CloudKey.ball, fileName: "ball.png")
        }
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.applyCloudChange() }
        }
        cloud.synchronize()
    }

    /// Re-read the synced values when another device changes them. The guard flag
    /// stops the resulting `didSet` from echoing the change straight back to iCloud.
    private func applyCloudChange() {
        applyingCloudChange = true
        defer { applyingCloudChange = false }
        if let raw = cloud.array(forKey: CloudKey.cardOrder) as? [String] {
            let saved = raw.compactMap(InfoCardKind.init(rawValue:))
            cardOrder = saved + InfoCardKind.allCases.filter { !saved.contains($0) }
        }
        if let raw = cloud.array(forKey: CloudKey.hiddenCards) as? [String] {
            hiddenCards = Set(raw.compactMap(InfoCardKind.init(rawValue:)))
        }
        if let hex = cloud.string(forKey: CloudKey.backgroundColor) { backgroundColorHex = hex }
        if cloud.object(forKey: CloudKey.clock) != nil { useBroadcastClock = cloud.bool(forKey: CloudKey.clock) }
        if let data = cloud.data(forKey: CloudKey.badge) { badgeImage = UIImage(data: data) }
        if let data = cloud.data(forKey: CloudKey.ball) { ballImage = UIImage(data: data) }
    }

    // MARK: Focus match

    var focusMatch: Match? {
        if demoMode { return DemoData.match(scene: DemoData.scenes[demoSceneIndex], sceneStart: demoSceneStart) }
        return liveFocus
    }

    /// What the live screen should show: a manually-picked match, else the live
    /// match, else the just-shown match for 2 minutes after it turns .finished, else
    /// nil (which makes the screen show the "no match live" placeholder).
    private func resolveLiveFocus() -> Match? {
        let matches = tournament.matches

        if let id = selectedMatchID, let m = matches.first(where: { $0.id == id }) {
            graceCandidateID = nil; graceFinishedAt = nil
            return m
        }

        if let live = tournament.liveMatches.first {
            // Track the live match so we can linger on it once it finishes.
            graceCandidateID = live.id
            graceFinishedAt = nil
            return live
        }

        // No live match: keep the match we were showing for 2 minutes after the API
        // reports it .finished (timed from when we first observed that), then nil.
        if let id = graceCandidateID, let m = matches.first(where: { $0.id == id }),
           m.phase() == .finished {
            if graceFinishedAt == nil { graceFinishedAt = Date() }
            if let finishedAt = graceFinishedAt, Date().timeIntervalSince(finishedAt) < endGrace {
                return m
            }
        }
        return nil
    }

    /// Recompute the live focus, triggering a detail fetch when the focused match changes.
    private func refreshFocus(dataChanged: Bool) {
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
        // Real ball position from the ESPN commentary feed when available.
        if let p = detail?.ballPoint { return p }
        guard let events = detail?.events else { return nil }
        let idx = events.lastIndex(where: { $0.isHome != nil })
        return BallEstimator.target(events: events, lastIndex: idx)
    }

    /// Whether the live ball is from real feed coordinates (vs. an estimate).
    var hasRealBall: Bool { !demoMode && detail?.ballPoint != nil }

    /// Located on-ball events for the possession heat map — the current mode's plays.
    var heatPoints: [HeatPoint] {
        let source = mode == .replay ? replayDetail : (demoMode ? nil : detail)
        return (source?.plays ?? []).compactMap { play in
            play.isHome.map { HeatPoint(point: play.point, isHome: $0) }
        }
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
        Self.endsSwitched(atMinute: currentReplayPlay?.minute ?? 0)
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
        switch newMode {
        case .replay:
            stopReplayTimer(); isPlaying = false
            stopDemoTicker()
            refreshReplayMatches(tournament.matches)
        case .standings:
            stopReplayTimer(); isPlaying = false
            stopDemoTicker()
        case .live:
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

    /// The playback steps: the match's real on-ball plays (ESPN coordinates), or —
    /// if a match has no coordinate data — its key events with an estimated ball.
    var replayPlays: [PlayPoint] {
        guard let detail = replayDetail else { return [] }
        if !detail.plays.isEmpty { return detail.plays }
        return detail.events.enumerated().compactMap { i, e in
            guard e.isHome != nil else { return nil }
            return PlayPoint(minute: e.minute ?? 0, clockText: e.clockText, typeText: e.typeText,
                             isHome: e.isHome, text: e.text,
                             point: BallEstimator.target(events: detail.events, lastIndex: i))
        }
    }

    /// Whether the replay is using real feed coordinates (vs. estimated).
    var replayHasRealBall: Bool { replayDetail?.ballPoint != nil }

    var currentReplayPlay: PlayPoint? {
        guard replayPlays.indices.contains(replayIndex) else { return nil }
        return replayPlays[replayIndex]
    }

    var replayBall: PitchPoint? { currentReplayPlay?.point }

    /// A short trail of the ball's recent real positions.
    var replayTrail: [PitchPoint] {
        let plays = replayPlays
        let start = max(0, replayIndex - 8)
        guard start < replayIndex else { return [] }
        return plays[start..<replayIndex].map(\.point)
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
            if !replayPlays.isEmpty { playReplay() }
        }
    }

    func playReplay() {
        guard !replayPlays.isEmpty else { return }
        isPlaying = true
        stopReplayTimer()
        replayTimer = Timer.scheduledTimer(withTimeInterval: 1.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.replayIndex < self.replayPlays.count - 1 {
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
