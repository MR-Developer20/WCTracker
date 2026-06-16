import SwiftUI
import UIKit

// MARK: - Brand palette (from the WorldCup26Widget scorebug)

enum Brand {
    static let barBlack = Color(red: 0.05, green: 0.05, blue: 0.07)
    static let mint = Color(red: 0.45, green: 0.96, blue: 0.79)
    static let cream = Color(red: 0.98, green: 0.96, blue: 0.92)
    static let pitchGreen = Color(red: 0.16, green: 0.52, blue: 0.24)
    static let pitchGreenDark = Color(red: 0.13, green: 0.45, blue: 0.21)

    /// The on-air glow: red left, aqua top, purple right, lime bottom.
    static var angular: AngularGradient {
        AngularGradient(
            colors: [
                Color(red: 0.62, green: 0.46, blue: 0.96),  // right: purple
                Color(red: 0.78, green: 0.93, blue: 0.25),  // bottom: lime
                Color(red: 0.96, green: 0.31, blue: 0.32),  // left: red
                Color(red: 0.45, green: 0.93, blue: 0.90),  // top: aqua
                Color(red: 0.62, green: 0.46, blue: 0.96),  // wrap
            ],
            center: .center
        )
    }
}

// MARK: - Team kit accent colors (the colored dot beside each code)

enum TeamAccent {
    private static let colors: [String: Color] = [
        "MEX": Color(red: 0.00, green: 0.55, blue: 0.30),
        "RSA": Color(red: 1.00, green: 0.78, blue: 0.05),
        "FRA": Color(red: 0.16, green: 0.35, blue: 0.85),
        "SEN": Color(red: 0.05, green: 0.65, blue: 0.35),
        "USA": Color(red: 0.85, green: 0.15, blue: 0.25),
        "CAN": Color(red: 0.90, green: 0.10, blue: 0.15),
        "BRA": Color(red: 1.00, green: 0.85, blue: 0.00),
        "ARG": Color(red: 0.45, green: 0.75, blue: 0.95),
        "GER": Color(red: 0.95, green: 0.95, blue: 0.95),
        "ESP": Color(red: 0.85, green: 0.10, blue: 0.15),
        "POR": Color(red: 0.80, green: 0.10, blue: 0.20),
        "NED": Color(red: 1.00, green: 0.45, blue: 0.00),
        "BEL": Color(red: 0.90, green: 0.15, blue: 0.20),
        "CRO": Color(red: 0.90, green: 0.20, blue: 0.20),
        "ITA": Color(red: 0.00, green: 0.35, blue: 0.70),
        "ENG": Color(red: 0.95, green: 0.95, blue: 0.95),
        "JPN": Color(red: 0.20, green: 0.30, blue: 0.80),
        "KOR": Color(red: 0.85, green: 0.15, blue: 0.25),
        "MAR": Color(red: 0.78, green: 0.12, blue: 0.20),
        "URU": Color(red: 0.45, green: 0.75, blue: 0.95),
        "COL": Color(red: 1.00, green: 0.85, blue: 0.00),
        "AUS": Color(red: 1.00, green: 0.78, blue: 0.05),
    ]

    static func color(for code: String) -> Color {
        colors[code.uppercased()] ?? .white.opacity(0.85)
    }
}

extension Color {
    /// Parse a 6-digit hex string like "FF8200" or "#ff8200"; nil if malformed.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }

    /// A team's kit color from its hex (if present) or the static accent map.
    static func kit(for team: Team) -> Color {
        team.colorHex.flatMap(Color.init(hex:)) ?? TeamAccent.color(for: team.code)
    }

    /// This color as a 6-digit hex string (no leading "#"), via its resolved sRGB components.
    func hexString() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X",
                      Int((r * 255).rounded()),
                      Int((g * 255).rounded()),
                      Int((b * 255).rounded()))
    }
}
