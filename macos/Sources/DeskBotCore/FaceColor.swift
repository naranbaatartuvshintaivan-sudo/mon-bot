import Foundation

// C# порт: src/DeskBot.App/UI/Controls/RobotFace.cs — ThemeColor, ColorOf, CurrentColor, Mix, Brighten, Hsv, ParseHex.
// WPF Color нь byte (0–255) тул truncation/rounding-ийг C#-тай ижил хийнэ
// (Math.Round = banker's rounding → .toNearestOrEven).

public struct RGBA: Hashable, Sendable {
    public var a: UInt8, r: UInt8, g: UInt8, b: UInt8

    public init(a: UInt8 = 255, r: UInt8, g: UInt8, b: UInt8) {
        self.a = a; self.r = r; self.g = g; self.b = b
    }

    public init(argb: UInt32) {
        self.init(a: UInt8(truncatingIfNeeded: argb >> 24), r: UInt8(truncatingIfNeeded: argb >> 16),
                  g: UInt8(truncatingIfNeeded: argb >> 8), b: UInt8(truncatingIfNeeded: argb))
    }

    public func withAlpha(_ a: UInt8) -> RGBA { RGBA(a: a, r: r, g: g, b: b) }

    public static let white = RGBA(r: 255, g: 255, b: 255)
    public static let classic = RGBA(r: 0x33, g: 0xE1, b: 0xFF)

    /// "#RRGGBB" — буруу бол Classic cyan.
    public static func parseHex(_ hex: String) -> RGBA {
        guard AppSettings.isHexColor(hex), let v = UInt32(hex.dropFirst(), radix: 16) else { return .classic }
        return RGBA(r: UInt8(truncatingIfNeeded: v >> 16), g: UInt8(truncatingIfNeeded: v >> 8), b: UInt8(truncatingIfNeeded: v))
    }

    public static func mix(_ x: RGBA, _ y: RGBA, _ t: Double) -> RGBA {
        let t = min(max(t, 0), 1)
        func l(_ p: UInt8, _ q: UInt8) -> UInt8 {
            UInt8((Double(p) + (Double(q) - Double(p)) * t).rounded(.toNearestOrEven))
        }
        return RGBA(a: l(x.a, y.a), r: l(x.r, y.r), g: l(x.g, y.g), b: l(x.b, y.b))
    }

    public static func brighten(_ c: RGBA, _ k: Double) -> RGBA {
        if k <= 1 {
            func s(_ v: UInt8) -> UInt8 { UInt8(max(0, Double(v) * k)) } // (byte) cast = truncation
            return RGBA(a: c.a, r: s(c.r), g: s(c.g), b: s(c.b))
        }
        return mix(c, RGBA(a: c.a, r: 255, g: 255, b: 255), min(1, (k - 1) * 0.6))
    }

    public static func hsv(_ h: Double, _ s: Double, _ v: Double) -> RGBA {
        let h = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let c = v * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        let (r, g, b): (Double, Double, Double) = switch Int(h / 60) {
        case 0: (c, x, 0)
        case 1: (x, c, 0)
        case 2: (0, c, x)
        case 3: (0, x, c)
        case 4: (x, 0, c)
        default: (c, 0, x)
        }
        func byte(_ u: Double) -> UInt8 { UInt8(min(255, max(0, (u + m) * 255))) }
        return RGBA(r: byte(r), g: byte(g), b: byte(b))
    }
}

public enum FacePalette {
    public static func themeColor(_ theme: FaceTheme, secondary: Bool = false, time: Double, customHex: String) -> RGBA {
        switch theme {
        case .aurora:
            secondary ? RGBA.hsv(275 + 35 * sin(time * 0.45 + 1.3), 0.75, 1) : RGBA.hsv(190 + 45 * sin(time * 0.6), 0.75, 1)
        case .matrix:
            secondary ? RGBA(r: 0x0F, g: 0x7A, b: 0x2E) : RGBA(r: 0x39, g: 0xFF, b: 0x6A)
        case .glitch:
            secondary ? RGBA(r: 0xFF, g: 0x3D, b: 0xF5) : RGBA(r: 0x7C, g: 0xF7, b: 0xFF)
        case .cyberpunk:
            secondary ? RGBA(r: 0xFF, g: 0xE1, b: 0x4D) : RGBA(r: 0xFF, g: 0x2E, b: 0x88)
        case .minimal:
            RGBA(r: 0xF2, g: 0xF5, b: 0xF7)
        case .custom:
            RGBA.parseHex(customHex)
        case .classic:
            secondary ? RGBA(r: 0x2A, g: 0x7B, b: 0xFF) : RGBA.classic
        }
    }

    /// Semantic өнгө (Angry/Error улаан, LowBattery шар) эсвэл theme өнгө.
    public static func color(of p: FaceParameters, theme: FaceTheme, time: Double, customHex: String) -> RGBA {
        if let u = p.semanticColor { return RGBA(argb: u) }
        return themeColor(theme, time: time, customHex: customHex)
    }

    /// Transition-ийн өнгө: from/to өнгийг холиод brightness-ээр гэрэлтүүлнэ.
    public static func current(from: FaceParameters, to: FaceParameters, t: Double, brightness: Double,
                               theme: FaceTheme, time: Double, customHex: String) -> RGBA {
        RGBA.brighten(RGBA.mix(color(of: from, theme: theme, time: time, customHex: customHex),
                               color(of: to, theme: theme, time: time, customHex: customHex), t),
                      brightness)
    }
}
