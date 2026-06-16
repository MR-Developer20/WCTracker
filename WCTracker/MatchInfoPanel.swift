import SwiftUI

/// The right 1/3: goals, team stats, stadium and weather for the focused match.
struct MatchInfoPanel: View {
    let detail: MatchDetail?
    let weather: MatchWeather?
    let home: Team
    let away: Team
    var isLoading: Bool
    var temperatureUnit: TemperatureUnit = .celsius
    var cards: [InfoCardKind] = InfoCardKind.allCases
    var onEditLayout: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if isLoading && detail == nil {
                    ProgressView("Loading match data…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }
                ForEach(cards) { cardView($0) }

                Button { onEditLayout() } label: {
                    Label("Customize Cards", systemImage: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.top, 2)
            }
            .padding(14)
        }
    }

    @ViewBuilder private func cardView(_ kind: InfoCardKind) -> some View {
        switch kind {
        case .goals: goalsCard
        case .teamStats: statsCard
        case .stadium: stadiumCard
        case .officials: officialsCard
        case .weather: weatherCard
        case .events: eventsCard
        case .leaders: leadersCard
        case .broadcasts: broadcastsCard
        case .news: newsCard
        case .videos: videosCard
        }
    }

    // MARK: Leaders

    private var leadersCard: some View {
        InfoCard(title: "Leaders", systemImage: "star.circle") {
            let leaders = detail?.leaders ?? []
            if leaders.isEmpty {
                EmptyHint("No leaders available")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(leaders) { team in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(team.code)
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(team.isHome ? Color.kit(for: home) : Color.kit(for: away))
                            ForEach(team.entries) { e in
                                HStack(spacing: 6) {
                                    Text(e.category).font(.system(size: 12)).foregroundStyle(.secondary)
                                    Spacer(minLength: 4)
                                    Text(e.player).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                    Text(e.value).font(.system(size: 12, weight: .heavy)).monospacedDigit()
                                        .foregroundStyle(.white).frame(minWidth: 24, alignment: .trailing)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Broadcasts

    private var broadcastsCard: some View {
        InfoCard(title: "Where to Watch", systemImage: "tv") {
            let casts = detail?.broadcasts ?? []
            if casts.isEmpty {
                EmptyHint("No broadcast info")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(casts) { b in
                        HStack(spacing: 8) {
                            Image(systemName: b.kind.lowercased().contains("stream") ? "play.tv" : "tv")
                                .font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 20)
                            Text(b.name).font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Text(b.kind).font(.system(size: 11)).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: News

    private var newsCard: some View {
        InfoCard(title: "News", systemImage: "newspaper") {
            let items = detail?.articles ?? []
            if items.isEmpty {
                EmptyHint("No news")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items) { item in
                        linkRow(item.headline, url: item.url, systemImage: "doc.text")
                    }
                }
            }
        }
    }

    // MARK: Videos

    private var videosCard: some View {
        InfoCard(title: "Videos", systemImage: "play.rectangle") {
            let items = detail?.videos ?? []
            if items.isEmpty {
                EmptyHint("No videos")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(items) { v in
                        videoRow(v)
                    }
                }
            }
        }
    }

    @ViewBuilder private func videoRow(_ v: VideoItem) -> some View {
        let row = HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Brand.barBlack)
                if let thumb = v.thumbnail {
                    AsyncImage(url: thumb) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Image(systemName: "play.circle.fill").font(.system(size: 18)).foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: 64, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(v.headline).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                if let d = v.duration {
                    Text(String(format: "%d:%02d", d / 60, d % 60))
                        .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        if let url = v.url {
            Link(destination: url) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }

    @ViewBuilder private func linkRow(_ text: String, url: URL?, systemImage: String) -> some View {
        let row = HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 18)
            Text(text).font(.system(size: 13)).foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if url != nil { Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(.tertiary) }
        }
        if let url { Link(destination: url) { row }.buttonStyle(.plain) } else { row }
    }

    // MARK: Goals

    private var goalsCard: some View {
        InfoCard(title: "Goals", systemImage: "soccerball.inverse") {
            let goals = detail?.goals ?? []
            if goals.isEmpty {
                EmptyHint(goalsHintText)
            } else {
                VStack(spacing: 8) {
                    ForEach(goals) { goal in
                        HStack(spacing: 8) {
                            Text((goal.isHome ? home : away).flag).font(.system(size: 17))
                            Text(goal.clockText.isEmpty ? "" : goal.clockText)
                                .font(.system(size: 14, weight: .heavy)).monospacedDigit()
                                .foregroundStyle(.secondary).frame(width: 38, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text(goal.scorer).font(.system(size: 15, weight: .semibold))
                                    if goal.isPenalty { tag("PEN") }
                                    if goal.isOwnGoal { tag("OG") }
                                }
                                if let assist = goal.assist {
                                    Text("assist: \(assist)").font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    private var goalsHintText: String {
        guard let detail else { return "—" }
        return detail.hasLineups ? "No goals yet" : "No goal data"
    }

    private func tag(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .black))
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(.orange.opacity(0.25), in: Capsule())
    }

    // MARK: Team stats

    private var statsCard: some View {
        InfoCard(title: "Team Stats", systemImage: "chart.bar.xaxis") {
            let stats = detail?.stats ?? []
            VStack(spacing: 12) {
                HStack {
                    Text(home.code).font(.system(size: 14, weight: .heavy)).foregroundStyle(Color.kit(for: home))
                    Spacer()
                    Text(away.code).font(.system(size: 14, weight: .heavy)).foregroundStyle(Color.kit(for: away))
                }
                formationRow
                if stats.isEmpty {
                    EmptyHint("No stats available")
                } else {
                    ForEach(stats) { stat in
                        StatBar(stat: stat, homeColor: Color.kit(for: home), awayColor: Color.kit(for: away))
                    }
                }
            }
        }
    }

    /// Each team's formation ("number strategy"), e.g. 4-3-3.
    @ViewBuilder private var formationRow: some View {
        let homeF = detail?.homeLineup?.formation
        let awayF = detail?.awayLineup?.formation
        if homeF != nil || awayF != nil {
            HStack {
                Text(homeF ?? "—").font(.system(size: 15, weight: .heavy)).monospacedDigit()
                Spacer()
                Text("Formation").font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
                Text(awayF ?? "—").font(.system(size: 15, weight: .heavy)).monospacedDigit()
            }
        }
    }

    // MARK: Stadium

    private var stadiumCard: some View {
        InfoCard(title: "Stadium", systemImage: "sportscourt") {
            if let venue = detail?.venue, venue.name != nil || !venue.locationLine.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    if let name = venue.name {
                        Text(name).font(.system(size: 17, weight: .bold))
                    }
                    if !venue.locationLine.isEmpty {
                        Label(venue.locationLine, systemImage: "mappin.and.ellipse")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    if let attendance = venue.attendance {
                        Label("\(attendance.formatted()) attendance", systemImage: "person.3.fill")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                EmptyHint("No venue data")
            }
        }
    }

    // MARK: Officials & format

    private var officialsCard: some View {
        InfoCard(title: "Officials", systemImage: "whistle") {
            let officials = detail?.officials ?? []
            VStack(alignment: .leading, spacing: 6) {
                if officials.isEmpty {
                    EmptyHint("No officials listed")
                } else {
                    ForEach(officials) { o in
                        HStack {
                            Text(o.name).font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Text(o.role).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                }
                if let format = detail?.format {
                    Divider().overlay(.white.opacity(0.1))
                    HStack {
                        Label("Format", systemImage: "clock")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(format.summary) (\(format.regulationMinutes)′)")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Weather

    private var weatherCard: some View {
        InfoCard(title: "Weather", systemImage: "cloud.sun") {
            if let weather {
                HStack(spacing: 14) {
                    Image(systemName: weather.symbolName)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 40))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(temperatureUnit.display(celsius: weather.temperatureC)).font(.system(size: 30, weight: .heavy))
                        Text(weather.condition).font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 5) {
                        if let wind = weather.windKph {
                            Label("\(Int(wind.rounded())) km/h", systemImage: "wind")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        if let humidity = weather.humidity {
                            Label("\(humidity)%", systemImage: "humidity")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Text("via \(weather.source.rawValue)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                EmptyHint("Weather unavailable")
            }
        }
    }

    // MARK: Event feed

    private var eventsCard: some View {
        InfoCard(title: "Match Events", systemImage: "list.bullet.rectangle") {
            let events = (detail?.events ?? []).filter { !($0.text ?? "").isEmpty || $0.kind != .other }
            if events.isEmpty {
                EmptyHint("No events yet")
            } else {
                VStack(spacing: 6) {
                    ForEach(events.reversed()) { event in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: icon(for: event.kind))
                                .font(.system(size: 13))
                                .foregroundStyle(color(for: event.kind))
                                .frame(width: 18)
                            Text(event.clockText)
                                .font(.system(size: 13, weight: .heavy)).monospacedDigit()
                                .foregroundStyle(.secondary).frame(width: 38, alignment: .leading)
                            Text(event.text?.isEmpty == false ? event.text! : event.typeText)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    private func icon(for kind: MatchEvent.Kind) -> String {
        switch kind {
        case .goal: return "soccerball"
        case .yellow: return "square.fill"
        case .red: return "square.fill"
        case .sub: return "arrow.left.arrow.right"
        case .varReview: return "tv"
        case .whistle: return "flag.checkered"
        case .other: return "circle.fill"
        }
    }

    private func color(for kind: MatchEvent.Kind) -> Color {
        switch kind {
        case .goal: return .green
        case .yellow: return .yellow
        case .red: return .red
        case .sub: return .blue
        case .varReview: return .purple
        case .whistle: return .secondary
        case .other: return .secondary
        }
    }
}

// MARK: - Stat comparison bar

private struct StatBar: View {
    let stat: TeamStat
    let homeColor: Color
    let awayColor: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(stat.homeText).font(.system(size: 14, weight: .bold)).monospacedDigit()
                Spacer()
                Text(stat.label).font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
                Text(stat.awayText).font(.system(size: 14, weight: .bold)).monospacedDigit()
            }
            GeometryReader { geo in
                let frac = homeFraction
                HStack(spacing: 2) {
                    Capsule().fill(homeColor).frame(width: max(2, geo.size.width * frac - 1))
                    Capsule().fill(awayColor)
                }
            }
            .frame(height: 6)
        }
    }

    private var homeFraction: Double {
        let h = stat.homeValue ?? 0, a = stat.awayValue ?? 0
        let total = h + a
        return total > 0 ? h / total : 0.5
    }
}

// MARK: - Reusable card + hints

struct InfoCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(.white.opacity(0.9))
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.10), lineWidth: 1))
    }
}

private struct EmptyHint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }
}
