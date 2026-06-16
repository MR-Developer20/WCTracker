import SwiftUI

/// A football pitch with both teams' players in formation and an animated ball.
/// Reused by live mode and replay mode (both place players by formation and move
/// the ball from the event feed — no free positional feed exists).
struct PitchView: View {
    var homeLineup: Lineup?
    var awayLineup: Lineup?
    var ball: PitchPoint?
    /// Recent ball positions, faded oldest → newest (used by replay).
    var trail: [PitchPoint] = []
    /// User-supplied ball image; falls back to a soccerball symbol when nil.
    var ballImage: UIImage? = nil
    var homeCode: String?
    var awayCode: String?
    var caption: String?
    /// Teams change ends at halftime — when flipped, home is drawn on the right
    /// (attacking left) and away on the left, mirroring the real match.
    var flipped: Bool = false
    /// Possession heat-map points (team-relative, canonical) and whether to show them.
    var heatPoints: [HeatPoint] = []
    var showHeat: Bool = false
    /// Tapping a player marker (used to show per-player stats).
    var onSelectPlayer: ((LineupPlayer) -> Void)? = nil

    private let margin: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Canvas { ctx, _ in drawField(ctx, size: size) }

                // Possession heat map (drawn over the grass, under the players).
                if showHeat && !heatPoints.isEmpty {
                    Canvas { ctx, _ in drawHeat(ctx, size: size) }
                        .allowsHitTesting(false)
                }

                // Direction labels in each team's half (swap at halftime).
                let labelY = margin + 22
                let leftX = margin + 54
                let rightX = size.width - margin - 54
                let homeOnLeft = !flipped
                if let homeCode {
                    halfLabel(homeCode, attacking: homeOnLeft ? "▶" : "◀",
                              at: CGPoint(x: homeOnLeft ? leftX : rightX, y: labelY), size: size)
                }
                if let awayCode {
                    halfLabel(awayCode, attacking: homeOnLeft ? "◀" : "▶",
                              at: CGPoint(x: homeOnLeft ? rightX : leftX, y: labelY), size: size)
                }

                // Players.
                ForEach(players) { player in
                    PlayerMarker(player: player,
                                 kit: kitColor(for: player),
                                 diameter: markerDiameter(size))
                        .contentShape(Rectangle())
                        .onTapGesture { onSelectPlayer?(player) }
                        .position(point(player.point, in: size))
                }

                // Ball trail (replay): faint dots brightening toward the current ball.
                ForEach(Array(trail.enumerated()), id: \.offset) { idx, p in
                    let frac = Double(idx + 1) / Double(max(trail.count, 1))
                    Circle()
                        .fill(.white.opacity(0.08 + 0.22 * frac))
                        .frame(width: 5 + 6 * frac, height: 5 + 6 * frac)
                        .position(point(p, in: size))
                }

                // Ball.
                if let ball {
                    BallMarker(image: ballImage, size: markerDiameter(size) * 0.8)
                        .position(point(ball, in: size))
                        .animation(.easeInOut(duration: 0.45), value: ball)
                }

                if let caption {
                    VStack {
                        Spacer()
                        Text(caption)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(.black.opacity(0.35), in: Capsule())
                            .padding(.bottom, 8)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var players: [LineupPlayer] {
        (homeLineup?.starters ?? []) + (awayLineup?.starters ?? [])
    }

    private func kitColor(for player: LineupPlayer) -> Color {
        let hex = player.isHome ? homeLineup?.colorHex : awayLineup?.colorHex
        return hex.flatMap(Color.init(hex:)) ?? (player.isHome ? .blue : .red)
    }

    private func heatColor(isHome: Bool) -> Color {
        let hex = isHome ? homeLineup?.colorHex : awayLineup?.colorHex
        return hex.flatMap(Color.init(hex:)) ?? (isHome ? .blue : .red)
    }

    /// Soft per-event blobs in each team's color; overlaps build the density map.
    /// Drawn in canonical orientation (not flipped) since it aggregates the match.
    private func drawHeat(_ ctx: GraphicsContext, size: CGSize) {
        let radius = min(size.width, size.height) * 0.11
        for hp in heatPoints {
            let c = CGPoint(x: margin + hp.point.x * (size.width - 2 * margin),
                            y: margin + hp.point.y * (size.height - 2 * margin))
            let color = heatColor(isHome: hp.isHome)
            let shading = GraphicsContext.Shading.radialGradient(
                Gradient(colors: [color.opacity(0.22), color.opacity(0)]),
                center: c, startRadius: 0, endRadius: radius)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius,
                                            width: radius * 2, height: radius * 2)),
                     with: shading)
        }
    }

    /// Marker size scales with the pitch width so 22 players + labels stay legible
    /// and don't overlap across device sizes (iPhone → iPad).
    private func markerDiameter(_ size: CGSize) -> CGFloat {
        min(38, max(20, size.width * 0.044))
    }

    // MARK: Coordinate mapping

    private func point(_ p: PitchPoint, in size: CGSize) -> CGPoint {
        let x = flipped ? (1 - p.x) : p.x
        return CGPoint(x: margin + x * (size.width - 2 * margin),
                       y: margin + p.y * (size.height - 2 * margin))
    }

    private func halfLabel(_ code: String, attacking: String, at pos: CGPoint, size: CGSize) -> some View {
        Text("\(code) \(attacking)")
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(.black.opacity(0.3), in: Capsule())
            .position(pos)
    }

    // MARK: Field drawing

    private func drawField(_ ctx: GraphicsContext, size: CGSize) {
        let rect = CGRect(x: margin, y: margin, width: size.width - 2 * margin, height: size.height - 2 * margin)

        // Mowing stripes.
        let stripes = 10
        let stripeW = rect.width / CGFloat(stripes)
        for i in 0..<stripes {
            let r = CGRect(x: rect.minX + CGFloat(i) * stripeW, y: rect.minY, width: stripeW, height: rect.height)
            ctx.fill(Path(r), with: .color(i % 2 == 0 ? Brand.pitchGreen : Brand.pitchGreenDark))
        }

        let white = GraphicsContext.Shading.color(.white.opacity(0.85))
        let lw: CGFloat = 2

        // Boundary.
        ctx.stroke(Path(rect), with: white, lineWidth: lw)
        // Halfway line.
        var half = Path(); half.move(to: CGPoint(x: rect.midX, y: rect.minY)); half.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        ctx.stroke(half, with: white, lineWidth: lw)
        // Center circle + spot.
        let cr = min(rect.width, rect.height) * 0.13
        ctx.stroke(Path(ellipseIn: CGRect(x: rect.midX - cr, y: rect.midY - cr, width: cr * 2, height: cr * 2)), with: white, lineWidth: lw)
        ctx.fill(Path(ellipseIn: CGRect(x: rect.midX - 3, y: rect.midY - 3, width: 6, height: 6)), with: white)

        // Penalty + goal areas, both ends.
        let penW = rect.width * 0.16
        let penH = rect.height * 0.56
        let goalW = rect.width * 0.06
        let goalH = rect.height * 0.28
        for leftSide in [true, false] {
            let boxX = leftSide ? rect.minX : rect.maxX - penW
            let pen = CGRect(x: boxX, y: rect.midY - penH / 2, width: penW, height: penH)
            ctx.stroke(Path(pen), with: white, lineWidth: lw)
            let gX = leftSide ? rect.minX : rect.maxX - goalW
            let goal = CGRect(x: gX, y: rect.midY - goalH / 2, width: goalW, height: goalH)
            ctx.stroke(Path(goal), with: white, lineWidth: lw)
            // Penalty spot.
            let spotX = leftSide ? rect.minX + penW * 0.66 : rect.maxX - penW * 0.66
            ctx.fill(Path(ellipseIn: CGRect(x: spotX - 2.5, y: rect.midY - 2.5, width: 5, height: 5)), with: white)
        }
    }
}

// MARK: - Player marker

private struct PlayerMarker: View {
    let player: LineupPlayer
    let kit: Color
    let diameter: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            marker
                .frame(width: diameter, height: diameter)
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                .opacity(player.subbedOut ? 0.45 : 1)
                .overlay(alignment: .topTrailing) {
                    // Subbed off ↓ / came on ↑ indicator.
                    if player.subbedOut || player.subbedIn {
                        Image(systemName: player.subbedIn ? "arrow.up" : "arrow.down")
                            .font(.system(size: diameter * 0.3, weight: .black))
                            .foregroundStyle(.white)
                            .padding(2)
                            .background(player.subbedIn ? .green : .red, in: Circle())
                            .offset(x: 3, y: -3)
                    }
                }

            // Number to the left of the name; scales with the marker so labels stay
            // legible without overlapping across device sizes.
            HStack(spacing: 3) {
                Text(player.number).font(.system(size: numberFont, weight: .heavy)).foregroundStyle(Brand.mint)
                Text(lastName(player.shortName)).font(.system(size: nameFont, weight: .semibold)).foregroundStyle(.white)
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 4).padding(.vertical, 1.5)
            .background(.black.opacity(0.55), in: Capsule())
        }
    }

    private var nameFont: CGFloat { min(13, max(8.5, diameter * 0.40)) }
    private var numberFont: CGFloat { min(12, max(8, diameter * 0.38)) }

    /// The headshot when the feed provides one, otherwise a kit-colored disc.
    @ViewBuilder private var marker: some View {
        if let url = player.headshotURL {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(kit)
            }
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
        } else {
            ZStack {
                Circle().fill(kit)
                Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5)
            }
        }
    }

    /// "R. Jiménez" → "Jiménez" to keep labels short on the pitch.
    private func lastName(_ s: String) -> String {
        if let last = s.split(separator: " ").last, s.contains(". ") { return String(last) }
        return s
    }
}

// MARK: - Ball marker

private struct BallMarker: View {
    var image: UIImage?
    var size: CGFloat = 26

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Image(systemName: "soccerball")
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(.white)
                    .background(Circle().fill(.black.opacity(0.25)).frame(width: size * 1.15, height: size * 1.15))
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 2)
    }
}
