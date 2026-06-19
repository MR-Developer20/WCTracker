import SwiftUI
import UIKit

/// The CarPlay scoreboard, split into three square tiles for a `CPListImageRowItem`'s
/// image row: home team, a center badge + clock tile, and away team. Each tile fills its
/// own ~95×95 pt slot, so the score / flag / badge render far larger than they would
/// crammed into a single tile. CarPlay lays the three across the row with its own spacing,
/// which reads like a broadcast scoreboard's segments. Everything is a plain value and the
/// flags are emoji (not `AsyncImage`), so the snapshots render synchronously with all of
/// it visible. `CarPlayInterface` rasterizes each tile.

/// Shared tile chrome: a black rounded square with the brand's angular glow border.
private func tileBackground() -> some View {
    ZStack {
        RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Brand.barBlack)
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .strokeBorder(Brand.angular, lineWidth: 3).opacity(0.9)
    }
    .background(
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .stroke(Brand.angular, lineWidth: 7).blur(radius: 10).opacity(0.5)
    )
}

/// One team's tile: flag, code, a kit-color accent, and a big mint score box.
struct CarPlayTeamTile: View {
    var flag: String
    var code: String
    var kit: Color
    /// nil score renders as "–" (upcoming match).
    var score: Int?

    var body: some View {
        VStack(spacing: 8) {
            Text(flag).font(.system(size: 52))
            Text(code).font(.system(size: 40, weight: .black)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.5)
            // Kit-color accent (the dots are invisible at this size; a bar isn't).
            Capsule().fill(kit).frame(width: 74, height: 8)
            Text(score.map(String.init) ?? "–")
                .font(.system(size: 80, weight: .black)).monospacedDigit()
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Brand.mint))
        }
        .padding(.horizontal, 22).padding(.vertical, 22)
        .frame(width: 300, height: 300)
        .background(tileBackground())
        .padding(12)   // breathing room so the glow isn't clipped in the snapshot
        .fixedSize()
    }
}

/// The center tile: tournament badge over the cream clock chip.
struct CarPlayCenterTile: View {
    var badge: UIImage?
    /// Pre-formatted clock string (MM:SS, "45'+2'", "HT", "FT", kickoff time…).
    var clock: String

    var body: some View {
        VStack(spacing: 18) {
            badgeView
            Text(clock)
                .font(.system(size: 40, weight: .black)).monospacedDigit()
                .foregroundStyle(.black)
                .lineLimit(1).minimumScaleFactor(0.5)
                .padding(.horizontal, 20).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.cream))
                .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
        }
        .padding(24)
        .frame(width: 300, height: 300)
        .background(tileBackground())
        .padding(12)
        .fixedSize()
    }

    @ViewBuilder private var badgeView: some View {
        if let badge {
            Image(uiImage: badge).resizable().scaledToFit().frame(height: 120)
        } else {
            // Neutral fallback — the app ships no trademarked emblem.
            VStack(spacing: 4) {
                Image(systemName: "trophy.fill").font(.system(size: 64)).foregroundStyle(Brand.mint)
                Text("WC 26").font(.system(size: 26, weight: .black)).foregroundStyle(.white)
            }
            .frame(height: 120)
        }
    }
}

#Preview {
    VStack(spacing: 30) {
        // Full size — read the detail.
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                CarPlayTeamTile(flag: "🇨🇦", code: "CAN", kit: TeamAccent.color(for: "CAN"), score: 3)
                CarPlayCenterTile(badge: nil, clock: "HT")
                CarPlayTeamTile(flag: "🇶🇦", code: "QAT", kit: TeamAccent.color(for: "QAT"), score: 0)
            }
            .scaleEffect(0.55)
        }
        // ~95 pt each — roughly the real CarPlay size.
        HStack(spacing: 6) {
            CarPlayTeamTile(flag: "🇫🇷", code: "FRA", kit: TeamAccent.color(for: "FRA"), score: nil)
            CarPlayCenterTile(badge: nil, clock: "20:00")
            CarPlayTeamTile(flag: "🇦🇷", code: "ARG", kit: TeamAccent.color(for: "ARG"), score: nil)
        }
        .scaleEffect(0.30)
    }
    .padding()
    .background(Color.black)
}
