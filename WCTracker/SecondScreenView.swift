import SwiftUI

// MARK: - Root second-screen layout

struct SecondScreenView: View {
    @ObservedObject var center: MatchCenterStore
    @State private var showSettings = false

    private var tournament: TournamentStore { center.tournament }

    var body: some View {
        ZStack {
            center.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .frame(height: 54)
                    .padding(.vertical, 10)

                GeometryReader { geo in
                    if center.mode == .live && center.focusMatch == nil {
                        noLiveMatchPlaceholder
                    } else {
                        HStack(spacing: 0) {
                            leftPane
                                .frame(width: geo.size.width * 2.0 / 3.0)
                                .padding(12)
                            rightPane
                                .frame(width: geo.size.width * 1.0 / 3.0)
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) { SettingsView(store: center) }
    }

    // MARK: Top bar

    private var topBar: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                // Left 2/3: scoreboard centered over the field view.
                scoreboardArea
                    .frame(width: geo.size.width * 2.0 / 3.0)
                // Right 1/3: controls over the info panel.
                controlsArea
                    .frame(width: geo.size.width * 1.0 / 3.0)
            }
        }
    }

    @ViewBuilder private var scoreboardArea: some View {
        Group {
            if center.mode == .live {
                BroadcastScoreboard(match: center.focusMatch,
                                    home: focusHome, away: focusAway)
            } else if let m = center.selectedReplayMatch {
                BroadcastScoreboard(match: m,
                                    home: tournament.team(for: m, home: true),
                                    away: tournament.team(for: m, home: false))
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
            Spacer(minLength: 0)
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
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
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
            Image("WC26Badge").resizable().scaledToFit().frame(height: 88).opacity(0.9)
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
                      homeCode: focusHome?.code,
                      awayCode: focusAway?.code,
                      caption: center.demoMode
                          ? "DEMO · sample formations & ball motion"
                          : "Player positions by formation · ball estimated from live events",
                      flipped: center.liveFlipped)
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
                          homeCode: tournament.team(for: match, home: true).code,
                          awayCode: tournament.team(for: match, home: false).code,
                          caption: replayCaption,
                          flipped: center.replayFlipped)
                replayTransport
            }
        } else if center.isLoadingReplay {
            pitchPlaceholder("Loading match…")
        } else {
            replayPicker
        }
    }

    private var replayCaption: String {
        guard let e = center.currentReplayEvent else { return "Step through the match events" }
        let clk = e.clockText.isEmpty ? "" : "\(e.clockText) "
        let who = e.playerName.map { " · \($0)" } ?? ""
        return "\(clk)\(e.typeText)\(who)  ·  positions estimated"
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
                   in: 0...Double(max(1, center.replayEvents.count - 1)))
            .tint(Brand.mint)

            Text(center.currentReplayEvent?.clockText ?? "")
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

    // MARK: Right pane (info)

    @ViewBuilder private var rightPane: some View {
        if center.mode == .live {
            MatchInfoPanel(detail: center.activeDetail,
                           weather: center.activeWeather,
                           home: focusHome ?? Team(id: "h", name: "Home", code: "HOM"),
                           away: focusAway ?? Team(id: "a", name: "Away", code: "AWY"),
                           isLoading: center.isLoadingDetail)
        } else {
            replayInfo
        }
    }

    private var replayInfo: some View {
        ScrollView {
            VStack(spacing: 14) {
                InfoCard(title: "Now", systemImage: "dot.radiowaves.left.and.right") {
                    if let e = center.currentReplayEvent {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(e.playerName ?? e.typeText).font(.system(size: 16, weight: .bold))
                            Text(e.clockText.isEmpty ? e.typeText : "\(e.clockText) · \(e.typeText)")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                            if let t = e.text, !t.isEmpty {
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
                InfoCard(title: "About replay", systemImage: "info.circle") {
                    Text("Steps through the real 2026 World Cup event timeline (via ESPN). Players are shown by formation and the ball is estimated from each event — no free API provides live positional tracking.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
    }
}

// MARK: - Broadcast scoreboard (ported look from the WorldCup26Widget scorebug)

struct BroadcastScoreboard: View {
    let match: Match?
    let home: Team?
    let away: Team?

    private let pillHeight: CGFloat = 40
    /// How far the clock chip's right edge slides underneath the bar.
    private let clockTuck: CGFloat = 44

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            if let match, let home, let away {
                HStack(alignment: .center, spacing: 8) {
                    clockColumn(match, now: ctx.date)
                    // Pull the bar left so it covers the chip's tucked cream edge
                    // (the bar is declared later, so it draws on top).
                    pill(match: match, home: home, away: away)
                        .padding(.leading, -(clockTuck + 8))
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
                if let over = stoppageElapsed(match, now: now) {
                    stoppageChip(over: over, plus: match.announcedAddedTime)
                        .fixedSize()
                        .offset(y: 30)
                }
            }
    }

    /// The minute the clock holds at while added time shows: 45 for first-half
    /// stoppage, 90 for second-half. nil during ordinary play (so it ticks normally).
    private func stoppageBoundary(_ match: Match) -> Int? {
        if let minute = match.minute, minute > 0 {
            if minute >= 90 { return 90 }
            if minute >= 45 && match.stoppagePlus != nil { return 45 }
            return nil
        }
        // Kickoff-anchored sources (demo) report no minute — fall back to the 90' mark.
        return match.stoppagePlus != nil ? 90 : nil
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
        // short HT/FT labels get a compact, content-sized pill instead.
        let compact = text == "HT" || text == "FT"
        return Text(text)
            .font(.system(size: 17, weight: .black)).monospacedDigit()
            .foregroundStyle(.black)
            .lineLimit(1).minimumScaleFactor(0.6)
            .frame(width: compact ? nil : 64, height: pillHeight)
            .padding(.horizontal, compact ? 14 : 0)
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
            guard let elapsed = match.elapsed(now: now) else { return "LIVE" }
            // Hold at the half's boundary (45:00 or 90:00) while added time shows.
            let cap = Double((stoppageBoundary(match) ?? 90) * 60)
            let capped = min(elapsed, cap)
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
                Color.clear.frame(width: 20, height: pillHeight)
                scoreBox(away, tuck: .leading)
            }
            badge
        }
    }

    private func teamSide(_ team: Team, leading: Bool) -> some View {
        HStack(spacing: 6) {
            if leading {
                flagView(team)
                Circle().fill(Color.kit(for: team)).frame(width: 7, height: 7)
                Text(team.code).font(.system(size: 19, weight: .black)).foregroundStyle(.white)
            } else {
                Text(team.code).font(.system(size: 19, weight: .black)).foregroundStyle(.white)
                Circle().fill(Color.kit(for: team)).frame(width: 7, height: 7)
                flagView(team)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: pillHeight)
    }

    /// Country flag from the API (ESPN `team.logo`), falling back to the emoji flag.
    @ViewBuilder private func flagView(_ team: Team) -> some View {
        if let url = team.flagURL {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Text(team.flag).font(.system(size: 18))
            }
            .frame(width: 26, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        } else {
            Text(team.flag).font(.system(size: 18))
        }
    }

    /// The inner edge extends 14pt toward the center so the mint slides under the
    /// badge (which draws on top); the digit stays centered in the visible 26pt.
    private func scoreBox(_ score: Int?, tuck edge: Edge.Set) -> some View {
        Text(score.map(String.init) ?? "–")
            .font(.system(size: 20, weight: .black)).monospacedDigit()
            .foregroundStyle(.black)
            .frame(width: 26, height: pillHeight - 4)
            .padding(edge, 14)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Brand.mint))
    }

    private var badge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Brand.barBlack)
            Image("WC26Badge")
                .resizable()
                .scaledToFit()
                .padding(1)
        }
        .frame(width: 40, height: pillHeight + 10)
        .shadow(color: .black.opacity(0.4), radius: 3)
    }
}
