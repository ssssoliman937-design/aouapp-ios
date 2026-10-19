import AOUHubCore
import SwiftUI

extension Color {
    init(_ argb: ARGB?) {
        guard let argb else { self = .clear; return }
        self = Color(.sRGB, red: argb.red, green: argb.green, blue: argb.blue, opacity: argb.alpha)
    }
}

/// shared/design/tokens.json resolved for one color scheme — the same values
/// android/lib/theme/v5.dart uses (V5.light / V5.dark).
struct Palette {
    let isDark: Bool
    private let tokens: DesignTokens
    private let mode: DesignTokens.Mode

    init(tokens: DesignTokens, scheme: ColorScheme) {
        self.tokens = tokens
        isDark = scheme == .dark
        mode = isDark ? .dark : .light
    }

    /// Any color token by name (bg, accent, okSoft…); course tiles use this.
    func tone(_ name: String) -> Color { Color(tokens.color(name, mode)) }
    private func navy(_ shade: String) -> Color { Color(tokens.navy[shade].flatMap(ARGB.init(hex:))) }

    var bg: Color { tone("bg") }
    var surface: Color { tone("surface") }
    var elevated: Color { tone("elevated") }
    var sheet: Color { tone("sheet") }
    var text: Color { tone("text") }
    var text2: Color { tone("text2") }
    var text3: Color { tone("text3") }
    var separator: Color { tone("separator") }
    var separatorStrong: Color { tone("separatorStrong") }
    var fill2: Color { tone("fill2") }
    var accent: Color { tone("accent") }
    var accentSoft: Color { tone("accentSoft") }
    var urgent: Color { tone("urgent") }
    var urgentSoft: Color { tone("urgentSoft") }
    var warn: Color { tone("warn") }
    var warnSoft: Color { tone("warnSoft") }
    var info: Color { tone("info") }
    var ok: Color { tone("ok") }
    var okSoft: Color { tone("okSoft") }
    var hero: [Color] { tokens.gradient("hero", mode).map { Color($0) } }

    /// Primary button fill: navy-800 in light, navy-500 in dark (Android FilledButton).
    var cta: Color { navy(isDark ? "500" : "800") }
    /// University chip / brand text: navy in light, plain text in dark.
    var brandInk: Color { isDark ? text : navy("800") }
    /// BrandMark tile color (android/lib/ui/auth/brand_mark.dart).
    var markTile: Color { isDark ? Color(red: 0x1E / 255, green: 0x4F / 255, blue: 0x8A / 255) : navy("800") }

    func toneName(for type: EventType) -> String {
        switch type {
        case .exam, .assignment: "urgent"
        case .quiz: "warn"
        case .lecture: "info"
        case .event: "ok"
        }
    }

    var heroBackground: some View {
        ZStack {
            LinearGradient(colors: hero, startPoint: UnitPoint(x: 0.34, y: 0), endPoint: UnitPoint(x: 0.66, y: 1))
            RadialGradient(
                colors: [Color(red: 0.31, green: 0.63, blue: 1).opacity(isDark ? 0.30 : 0.38), .clear],
                center: .topTrailing, startRadius: 0, endRadius: 260
            )
        }
    }
}

enum AppFont {
    static let family = "Cairo"

    static func body(_ size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
        .custom(family, size: size).weight(weight)
    }
}

/// The official AOU arch + three stepped bars (shared/icons/aou-mark.svg,
/// 143×215, even-odd) — same geometry as Android's aouMarkPath().
struct AOUMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width / 143, rect.height / 215)
        let ox = rect.midX - 143 * s / 2, oy = rect.midY - 215 * s / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        var path = Path()
        path.move(to: p(0, 71.5))
        path.addArc(center: p(71.5, 71.5), radius: 71.5 * s, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: p(143, 215))
        path.addLine(to: p(0, 215))
        path.closeSubpath()
        for (x, y, w) in [(67.0, 93.0, 61.0), (41, 134, 87), (15, 175, 113)] {
            path.addRect(CGRect(origin: p(x, y), size: CGSize(width: w * s, height: 25 * s)))
        }
        return path
    }
}

struct BrandMark: View {
    @Environment(\.palette) private var palette
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(LinearGradient(colors: [palette.markTile.opacity(0.9), palette.markTile], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(AOUMarkShape().fill(.white, style: FillStyle(eoFill: true)).frame(height: size * 0.62))
            .accessibilityLabel("Arab Open University")
    }
}
