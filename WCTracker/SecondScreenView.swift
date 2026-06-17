import SwiftUI
import UIKit

// MARK: - Root second-screen layout

struct SecondScreenView: View {
    @ObservedObject var center: MatchCenterStore
    @State private var showSettings = false
    @State private var selectedPlayer: LineupPlayer?
    @State private var showCardEditor = false

    private var tournament: TournamentStore { center.tournament }

    /// The scoreboard reads bigger on iPad's larger canvas.
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var scoreboardScale: CGFloat { isPad ? 1.3 : 0.8 }
    private var topBarHeight: CGFloat { isPad ? 88 : 54 }
    private var topBarPadding: CGFloat { isPad ? 10 : 6 }

    /// The right-hand info-card column takes a bigger share on iPhone (where the
    /// broadcast-style 1/3 is too cramped for the cards); iPad keeps the 1/3 look.
    /// The pitch (and the scoreboard above it) take the rest.
    private var cardFraction: CGFloat { isPad ? 1.0 / 3.0 : 0.42 }
    private var pitchFraction: CGFloat { 1 - cardFraction }

    /// Real football-pitch proportions (≈105×68 m), kept constant across devices so
    /// the field reads the same on iPad as on iPhone instead of stretching to a square.
    private static let pitchAspect: CGFloat = 1.55

    var body: some View {
        ZStack {
            center.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .frame(height: topBarHeight)
                    .padding(.vertical, topBarPadding)

                GeometryReader { geo in
                    if center.mode == .standings {
                        StandingsView(tournament: tournament)
                    } else if center.mode == .live && center.focusMatch == nil {
                        noLiveMatchPlaceholder
                    } else {
                        // Pane widths + side margins + the gap sum to the full width
                        // (so the right cards aren't pushed off-screen). pad == gap
                        // keeps the pitch centered under the scoreboard.
                        let pad: CGFloat = 12, gap: CGFloat = 12
                        let usable = geo.size.width - pad * 2 - gap
                        HStack(spacing: gap) {
                            leftPane
                                .frame(width: usable * pitchFraction)
                            rightPane
                                .frame(width: usable * cardFraction)
                        }
                        .padding(.horizontal, pad)
                        .padding(.bottom, 10)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) { SettingsView(store: center) }
        .sheet(item: $selectedPlayer) { PlayerStatsSheet(player: $0) }
        .sheet(isPresented: $showCardEditor) { CardLayoutEditor(store: center) }
    }

    // MARK: Top bar

    private var topBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .trailing) {
                // Scoreboard centered over the pitch pane (matches the content split).
                scoreboardArea
                    .frame(width: geo.size.width * pitchFraction)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Controls always pinned to the right edge, in every mode and state.
                controlsArea
            }
        }
    }

    @ViewBuilder private var scoreboardArea: some View {
        Group {
            if center.mode == .standings {
                Text("Group Standings")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.white)
            } else if center.mode == .live {
                // Hidden entirely when there's no match to show.
                if let match = center.focusMatch {
                    BroadcastScoreboard(match: match,
                                        home: focusHome, away: focusAway,
                                        badgeImage: center.badgeImage,
                                        half: center.activeDetail?.format?.halfMinutes ?? 45,
                                        broadcastClock: center.useBroadcastClock)
                        .scaleEffect(scoreboardScale)
                }
            } else if let m = center.selectedReplayMatch {
                BroadcastScoreboard(match: m,
                                    home: tournament.team(for: m, home: true),
                                    away: tournament.team(for: m, home: false),
                                    badgeImage: center.badgeImage,
                                    half: center.replayDetail?.format?.halfMinutes ?? 45,
                                    broadcastClock: center.useBroadcastClock)
                    .scaleEffect(scoreboardScale)
            } else {
                Text("Replay — pick a 2026 match")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity)   // center within the left 2/3
    }

    private var controlsArea: some View {
        HStack(spacing: 10) {
            if center.demoMode {
                Text("DEMO")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Brand.mint, in: Capsule())
            }
            if center.mode == .live && !center.demoMode { matchMenu }
            Picker("Mode", selection: Binding(
                get: { center.mode },
                set: { center.setMode($0) })) {
                Text("Live").tag(MatchCenterStore.Mode.live)
                Text("Replay").tag(MatchCenterStore.Mode.replay)
                Text("Table").tag(MatchCenterStore.Mode.standings)
            }
            .pickerStyle(.segmented)
            .frame(width: isPad ? 210 : 168)
            .fixedSize()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill").font(.system(size: 18))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.trailing, 16)
    }

    private var matchMenu: some View {
        Menu {
            Button("Auto (live only)") { center.selectedMatchID = nil }
            let now = Date()
            let live = tournament.matches.filter { $0.phase(now: now) == .live }
            let upcoming = tournament.matches.filter { $0.phase(now: now) == .upcoming }.prefix(12)
            let finished = tournament.matches.filter { $0.phase(now: now) == .finished }.suffix(12).reversed()
            if !live.isEmpty {
                Section("Live") { ForEach(live) { menuRow($0) } }
            }
            if !finished.isEmpty {
                Section("Recent results") { ForEach(Array(finished)) { menuRow($0) } }
            }
            if !upcoming.isEmpty {
                Section("Upcoming") { ForEach(Array(upcoming)) { menuRow($0) } }
            }
        } label: {
            Image(systemName: "rectangle.stack.fill").font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func menuRow(_ match: Match) -> some View {
        let h = tournament.team(for: match, home: true)
        let a = tournament.team(for: match, home: false)
        return Button {
            center.selectedMatchID = match.id
        } label: {
            Text("\(h.code) \(match.homeScore)–\(match.awayScore) \(a.code)")
        }
    }

    private var focusHome: Team? { center.focusMatch.map { tournament.team(for: $0, home: true) } }
    private var focusAway: Team? { center.focusMatch.map { tournament.team(for: $0, home: false) } }

    // MARK: No-live-match placeholder

    private var noLiveMatchPlaceholder: some View {
        VStack(spacing: 14) {
            Group {
                if let badge = center.badgeImage {
                    Image(uiImage: badge).resizable().scaledToFit()
                } else {
                    Image(systemName: "trophy.fill").resizable().scaledToFit().foregroundStyle(Brand.mint)
                }
            }
            .frame(height: 80).opacity(0.9)
            Text("No match live right now")
                .font(.system(size: 24, weight: .heavy)).foregroundStyle(.white)
            if let next = nextUpcoming {
                let h = tournament.team(for: next, home: true)
                let a = tournament.team(for: next, home: false)
                VStack(spacing: 4) {
                    Text("NEXT MATCH").font(.system(size: 11, weight: .heavy)).foregroundStyle(.secondary)
                    Text("\(h.flag) \(h.code)  vs  \(a.code) \(a.flag)")
                        .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                    if let d = next.date {
                        Text(d.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    if let venue = next.venueName {
                        Text(venue).font(.system(size: 12)).foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 4)
            }
            Text("Switch to Replay to watch a finished match, or turn on Demo mode in Settings.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var nextUpcoming: Match? {
        let now = Date()
        return tournament.matches
            .filter { $0.phase(now: now) == .upcoming }
            .min { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    // MARK: Left pane (pitch)

    @ViewBuilder private var leftPane: some View {
        if center.mode == .live {
            livePitch
        } else {
            replayPitch
        }
    }

    @ViewBuilder private var livePitch: some View {
        if let detail = center.activeDetail, detail.hasLineups {
            PitchView(homeLineup: detail.homeLineup,
                      awayLineup: detail.awayLineup,
                      ball: center.ball,
                      ballImage: center.ballImage,
                      homeCode: focusHome?.code,
                      awayCode: focusAway?.code,
                      caption: center.demoMode
                          ? "DEMO · sample formations & ball motion"
                          : (center.hasRealBall
                              ? "Player positions by formation · live ball from ESPN"
                              : "Player positions by formation · ball estimated from live events"),
                      flipped: center.liveFlipped,
                      heatPoints: center.heatPoints,
                      showHeat: center.showHeatMap,
                      onSelectPlayer: { selectedPlayer = $0 })
                .aspectRatio(Self.pitchAspect, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) { heatToggle }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            pitchPlaceholder(center.isLoadingDetail ? "Loading lineups…" : "Lineups appear near kickoff")
        }
    }

    @ViewBuilder private var replayPitch: some View {
        if let match = center.selectedReplayMatch, let detail = center.replayDetail, detail.hasLineups {
            VStack(spacing: 10) {
                PitchView(homeLineup: detail.homeLineup,
                          awayLineup: detail.awayLineup,
                          ball: center.replayBall,
                          trail: center.replayTrail,
                          ballImage: center.ballImage,
                          homeCode: tournament.team(for: match, home: true).code,
                          awayCode: tournament.team(for: match, home: false).code,
                          caption: replayCaption,
                          flipped: center.replayFlipped,
                          heatPoints: center.heatPoints,
                          showHeat: center.showHeatMap,
                          onSelectPlayer: { selectedPlayer = $0 })
                    .aspectRatio(Self.pitchAspect, contentMode: .fit)
                    .overlay(alignment: .bottomTrailing) { heatToggle }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                replayTransport
            }
        } else if center.isLoadingReplay {
            pitchPlaceholder("Loading match…")
        } else {
            replayPicker
        }
    }

    private var replayCaption: String {
        guard let p = center.currentReplayPlay else { return "Step through the match — real ESPN coordinates" }
        let clk = p.clockText.isEmpty ? "" : "\(p.clockText) "
        return "\(clk)\(p.typeText)  ·  real ESPN coordinates"
    }

    private var replayTransport: some View {
        HStack(spacing: 12) {
            Button { center.toggleReplay() } label: {
                Image(systemName: center.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 30))
            }
            .buttonStyle(.plain).foregroundStyle(.white)

            Slider(value: Binding(
                get: { Double(center.replayIndex) },
                set: { center.pauseReplay(); center.replayIndex = Int($0) }),
                   in: 0...Double(max(1, center.replayPlays.count - 1)))
            .tint(Brand.mint)

            Text(center.currentReplayPlay?.clockText ?? "")
                .font(.system(size: 13, weight: .heavy)).monospacedDigit()
                .foregroundStyle(.white).frame(width: 44)

            Menu {
                ForEach(center.replayMatches) { m in
                    Button(replayLabel(m)) { Task { await center.selectReplay(m) } }
                }
            } label: {
                Image(systemName: "list.bullet").font(.system(size: 18)).foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 6)
    }

    private func replayLabel(_ m: Match) -> String {
        let h = tournament.team(for: m, home: true)
        let a = tournament.team(for: m, home: false)
        return "\(h.code) \(m.homeScore)–\(m.awayScore) \(a.code)"
    }

    private var replayPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Replay — 2026 World Cup")
                .font(.system(size: 18, weight: .heavy)).foregroundStyle(.white)
            Text("Step through a finished match's real event timeline. Pick a match:")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 10)], spacing: 10) {
                    ForEach(center.replayMatches) { m in
                        Button { Task { await center.selectReplay(m) } } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(replayLabel(m)).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                                if let venue = m.venueName {
                                    Text(venue).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if center.replayMatches.isEmpty {
                Text("No finished 2026 matches yet — check back after a match ends.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.top, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func pitchPlaceholder(_ text: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(Brand.pitchGreen.opacity(0.5))
            VStack(spacing: 10) {
                ProgressView().tint(.white)
                Text(text).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    /// Possession heat-map toggle, shown on the pitch when located plays exist.
    @ViewBuilder private var heatToggle: some View {
        if !center.heatPoints.isEmpty {
            Button { center.showHeatMap.toggle() } label: {
                Image(systemName: "flame.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(center.showHeatMap ? Brand.mint : .white.opacity(0.85))
                    .padding(8)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(10)
        }
    }

    // MARK: Right pane (info)

    @ViewBuilder private var rightPane: some View {
        if center.mode == .live {
            MatchInfoPanel(detail: center.activeDetail,
                           weather: center.activeWeather,
                           home: focusHome ?? Team(id: "h", name: "Home", code: "HOM"),
                           away: focusAway ?? Team(id: "a", name: "Away", code: "AWY"),
                           isLoading: center.isLoadingDetail,
                           temperatureUnit: center.temperatureUnit,
                           cards: center.visibleCards,
                           onEditLayout: { showCardEditor = true })
        } else {
            replayInfo
        }
    }

    private var replayInfo: some View {
        let match = center.selectedReplayMatch
        let homeColor = match.map { Color.kit(for: tournament.team(for: $0, home: true)) } ?? .blue
        let awayColor = match.map { Color.kit(for: tournament.team(for: $0, home: false)) } ?? .red
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    InfoCard(title: "Now", systemImage: "dot.radiowaves.left.and.right") {
                        if let p = center.currentReplayPlay {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(p.typeText).font(.system(size: 16, weight: .bold))
                                if !p.clockText.isEmpty {
                                    Text(p.clockText).font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                                if let t = p.text, !t.isEmpty {
                                    Text(t).font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text("Pick a match to start the replay.")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }

                    if !center.replayPlays.isEmpty {
                        InfoCard(title: "Timeline", systemImage: "list.bullet") {
                            VStack(spacing: 2) {
                                ForEach(Array(center.replayPlays.enumerated()), id: \.element.id) { idx, p in
                                    Button { center.pauseReplay(); center.replayIndex = idx } label: {
                                        HStack(spacing: 8) {
                                            Circle()
                                                .fill(p.isHome == true ? homeColor : (p.isHome == false ? awayColor : Color.gray))
                                                .frame(width: 7, height: 7)
                                            Text(p.clockText)
                                                .font(.system(size: 12, weight: .heavy)).monospacedDigit()
                                                .foregroundStyle(.secondary).frame(width: 38, alignment: .leading)
                                            Text(p.text?.isEmpty == false ? p.text! : p.typeText)
                                                .font(.system(size: 12))
                                                .foregroundStyle(idx == center.replayIndex ? .white : .white.opacity(0.75))
                                                .lineLimit(2)
                                                .fixedSize(horizontal: false, vertical: true)
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.vertical, 4).padding(.horizontal, 6)
                                        .background(idx == center.replayIndex ? Color.white.opacity(0.12) : .clear,
                                                    in: RoundedRectangle(cornerRadius: 6))
                                    }
                                    .buttonStyle(.plain)
                                    .id(idx)
                                }
                            }
                        }
                    }

                    InfoCard(title: "About replay", systemImage: "info.circle") {
                        Text("Steps through the 2026 World Cup match (via ESPN). Players are shown by formation; the ball follows the real on-ball coordinates ESPN reports for each play, where available.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
            }
            .onChange(of: center.replayIndex) { _, idx in
                withAnimation { proxy.scrollTo(idx, anchor: .center) }
            }
        }
    }
}

// MARK: - Broadcast scoreboard (ported look from the WorldCup26Widget scorebug)

struct BroadcastScoreboard: View {
    let match: Match?
    let home: Team?
    let away: Team?
    var badgeImage: UIImage? = nil
    /// Regulation half length in minutes (from the ESPN match format; default 45).
    var half: Int = 45
    /// Show ESPN's exact broadcast minute ("37'", "45'+2'") instead of synthesized MM:SS.
    var broadcastClock: Bool = false

    private let pillHeight: CGFloat = 52
    /// How far the clock chip's right edge slides underneath the bar.
    private let clockTuck: CGFloat = 54
    private var regulationEnd: Int { half * 2 }   // e.g. 90

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            if let match, let home, let away {
                // The pill is the layout anchor; the clock chip is a background pinned
                // to the pill's leading edge and extends to the LEFT (its right edge
                // tucks under the bar). So a wide clock grows into the empty space on
                // the left instead of pushing/squishing the team names.
                pill(match: match, home: home, away: away)
                    .background(alignment: .leading) {
                        clockColumn(match, now: ctx.date)
                            // Align the chip's text/tuck seam (width − tuck) to the
                            // pill's leading edge: text sits left, cream tuck under it.
                            .alignmentGuide(.leading) { d in d.width - clockTuck }
                    }
            } else {
                placeholder
            }
        }
    }

    /// Clock chip. During either half's added time the broadcast stoppage treatment
    /// shows: the main clock holds at 45:00 / 90:00 and a black sub-chip counts the
    /// overtime ("+6" announced in mint). The sub-chip is an overlay that floats
    /// below the chip so it never changes the (fixed) top-bar height.
    private func clockColumn(_ match: Match, now: Date) -> some View {
        clockChip(match, now: now)
            .overlay(alignment: .bottomLeading) {
                if broadcastClock {
                    // Accurate mode: show the "+N'" added time as its own pill so the
                    // main chip stays "45'"/"90'" and doesn't widen the clock. Hidden
                    // at HT (the feed freezes displayClock at "45'+x" through the break).
                    if match.phase(now: now) == .live, !match.isHalftime,
                       let added = broadcastAdded(match) {
                        overtimePill(added).fixedSize().offset(y: 30)
                    }
                } else if let over = stoppageElapsed(match, now: now) {
                    stoppageChip(over: over, plus: match.announcedAddedTime)
                        .fixedSize()
                        .offset(y: 30)
                }
            }
    }

    /// The "+N'" suffix of the broadcast clock ("45'+4'" → "+4'"); nil when not in
    /// added time.
    private func broadcastAdded(_ match: Match) -> String? {
        guard let dc = match.displayClock, let r = dc.range(of: "+") else { return nil }
        return String(dc[r.lowerBound...])
    }

    /// Added-time pill for accurate mode — mint "+N'" on the bar-black chip.
    private func overtimePill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .black))
            .foregroundStyle(Brand.mint)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Brand.barBlack))
            .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
    }

    /// The minute the clock holds at while added time shows — the current period's
    /// end (half, full time, or an extra-time half end). nil during ordinary play
    /// (incl. extra-time play before its added time), so the clock ticks normally.
    private func stoppageBoundary(_ match: Match) -> Int? {
        // Period ends from the format: half (45), full time (90), ET1 (105), ET2 (120).
        let ends = [half, regulationEnd, regulationEnd + 15, regulationEnd + 30]
        guard let minute = match.minute, minute > 0 else {
            // Kickoff-anchored sources (demo) report no minute — hold at full time.
            return match.stoppagePlus != nil ? regulationEnd : nil
        }
        guard match.stoppagePlus != nil else { return nil }
        return ends.last(where: { minute >= $0 })
    }

    /// Seconds past the half's regulation boundary while the feed reports added time.
    private func stoppageElapsed(_ match: Match, now: Date) -> TimeInterval? {
        guard match.phase(now: now) == .live, !match.isHalftime,
              let boundary = stoppageBoundary(match),
              let elapsed = match.elapsed(now: now),
              elapsed > Double(boundary * 60) else { return nil }
        return elapsed - Double(boundary * 60)
    }

    private func stoppageChip(over: TimeInterval, plus: Int?) -> some View {
        HStack(spacing: 6) {
            Text(String(format: "%d:%02d", Int(over) / 60, Int(over) % 60))
                .foregroundStyle(.white).monospacedDigit()
            if let plus {
                Text("+\(plus)").foregroundStyle(Brand.mint)
            }
        }
        .font(.system(size: 14, weight: .black))
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Brand.barBlack))
        .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
    }

    private var placeholder: some View {
        Text("FIFA WORLD CUP 26™")
            .font(.system(size: 15, weight: .black)).foregroundStyle(.white)
            .padding(.horizontal, 16).frame(height: pillHeight)
            .background(Brand.barBlack, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Brand.angular, lineWidth: 2).opacity(0.8))
    }

    private func clockChip(_ match: Match, now: Date) -> some View {
        let text = clockText(match, now: now)
        // Fixed width for the running clock so it doesn't jiggle each second; the
        // short HT/FT labels and the broadcast-minute string get a content-sized pill.
        let compact = broadcastClock || text == "HT" || text == "FT"
        return Text(text)
            .font(.system(size: 22, weight: .black)).monospacedDigit()
            .foregroundStyle(.black)
            .lineLimit(1).minimumScaleFactor(0.6)
            .frame(width: compact ? nil : 80, height: pillHeight)
            .padding(.horizontal, compact ? 16 : 0)
            // Extra cream that slides underneath the bar; the digits stay clear.
            .padding(.trailing, clockTuck)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.cream))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
    }

    private func clockText(_ match: Match, now: Date) -> String {
        switch match.phase(now: now) {
        case .finished: return "FT"
        case .upcoming:
            guard let date = match.date else { return "--:--" }
            let df = DateFormatter()
            df.dateFormat = Calendar.current.isDate(date, inSameDayAs: now) ? "HH:mm" : "MMM d"
            return df.string(from: date)
        case .live:
            if match.isHalftime { return "HT" }
            // Exact broadcast minute when the user prefers it — base minute only
            // ("45'+2'" → "45'"); the "+2'" added time shows in its own pill.
            if broadcastClock, let dc = match.displayClock, !dc.isEmpty {
                if let r = dc.range(of: "+") { return String(dc[..<r.lowerBound]) }
                return dc
            }
            guard let elapsed = match.elapsed(now: now) else { return "LIVE" }
            // Hold at the period boundary during added time; otherwise tick freely
            // (so normal play — including extra time past 90' — counts up).
            let capped = stoppageBoundary(match).map { min(elapsed, Double($0 * 60)) } ?? elapsed
            return String(format: "%02d:%02d", Int(capped) / 60, Int(capped) % 60)
        }
    }

    private func pill(match: Match, home: Team, away: Team) -> some View {
        let isUpcoming = match.phase() == .upcoming
        // The bar (fill + glow) is height-constrained so the score boxes tuck under
        // the centered badge, which draws on top — mirrors the WorldCup26Widget scorebug.
        return HStack(spacing: 0) {
            teamSide(home, leading: true)
            centerGroup(home: isUpcoming ? nil : match.homeScore,
                        away: isUpcoming ? nil : match.awayScore)
            teamSide(away, leading: false)
        }
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.barBlack)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Brand.angular, lineWidth: 2).opacity(0.85)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Brand.angular, lineWidth: 5).blur(radius: 6).opacity(0.5)
            )
            .frame(height: pillHeight)
        }
        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
    }

    /// Score boxes flanking the tournament badge. The badge is centered on this
    /// group and draws on top of the boxes' tucked mint, so it lands between the
    /// scores regardless of the surrounding team-code widths.
    private func centerGroup(home: Int?, away: Int?) -> some View {
        ZStack {
            HStack(spacing: 0) {
                scoreBox(home, tuck: .trailing)
                Color.clear.frame(width: 24, height: pillHeight)
                scoreBox(away, tuck: .leading)
            }
            badge
        }
    }

    private func teamSide(_ team: Team, leading: Bool) -> some View {
        HStack(spacing: 8) {
            if leading {
                flagView(team)
                Circle().fill(Color.kit(for: team)).frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.5))
                Text(team.code).font(.system(size: 24, weight: .black)).foregroundStyle(.white)
                    .lineLimit(1).fixedSize()
            } else {
                Text(team.code).font(.system(size: 24, weight: .black)).foregroundStyle(.white)
                    .lineLimit(1).fixedSize()
                Circle().fill(Color.kit(for: team)).frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.5))
                flagView(team)
            }
        }
        .padding(.horizontal, 13)
        .frame(height: pillHeight)
    }

    /// Country flag from the API (ESPN `team.logo`), falling back to the emoji flag.
    @ViewBuilder private func flagView(_ team: Team) -> some View {
        if let url = team.flagURL {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Text(team.flag).font(.system(size: 22))
            }
            .frame(width: 32, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        } else {
            Text(team.flag).font(.system(size: 22))
        }
    }

    /// The inner edge extends toward the center so the mint slides under the badge
    /// (which draws on top); the digit stays centered in the visible width.
    private func scoreBox(_ score: Int?, tuck edge: Edge.Set) -> some View {
        Text(score.map(String.init) ?? "–")
            .font(.system(size: 26, weight: .black)).monospacedDigit()
            .foregroundStyle(.black)
            .frame(width: 32, height: pillHeight - 4)
            .padding(edge, 16)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Brand.mint))
    }

    private var badge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Brand.barBlack)
            if let badgeImage {
                Image(uiImage: badgeImage)
                    .resizable()
                    .scaledToFit()
                    .padding(1)
            } else {
                // Neutral fallback — the app ships no trademarked emblem.
                VStack(spacing: 1) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Brand.mint)
                    Text("WC 26")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: 50, height: pillHeight + 12)
        .shadow(color: .black.opacity(0.4), radius: 3)
    }
}
