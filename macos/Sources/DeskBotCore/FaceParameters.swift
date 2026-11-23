// C# порт: src/DeskBot.Core/Expressions/FaceParameters.cs — тоо бүр C#-тай ЯГ ижил байх ёстой.

public struct FaceOverlay: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let sparkles = FaceOverlay(rawValue: 1 << 0)
    public static let ring = FaceOverlay(rawValue: 1 << 1)
    public static let wave = FaceOverlay(rawValue: 1 << 2)
    public static let pixelX = FaceOverlay(rawValue: 1 << 3)
    public static let bubble = FaceOverlay(rawValue: 1 << 4)
    public static let clock = FaceOverlay(rawValue: 1 << 5)
    public static let battery = FaceOverlay(rawValue: 1 << 6)
    public static let notes = FaceOverlay(rawValue: 1 << 7)
    public static let question = FaceOverlay(rawValue: 1 << 8)
    public static let zzz = FaceOverlay(rawValue: 1 << 9)
    public static let warning = FaceOverlay(rawValue: 1 << 10)
    public static let check = FaceOverlay(rawValue: 1 << 11)   // macOS-only: Copied
}

/// Нүдний хэлбэрийг тодорхойлох цэвэр тоон параметрүүд. Renderer эдгээрийг lerp хийж
/// expression хооронд зөөлөн шилжинэ. Бүх хэмжээ нь base eye size-тай харьцангуй.
public struct FaceParameters: Hashable, Sendable {
    public var eyeWidth: Double = 1        // 1 = default
    public var eyeHeight: Double = 1
    public var lidTop: Double = 0          // 0..1 — дээрээс хучих хэсэг
    public var lidAngle: Double = 0        // градус. + = дотор тал доош (уурласан), − = гадна тал доош (гунигтай)
    public var bottomCut: Double = 0       // 0..1 — доороос эллипсээр тайрах (∩ баярласан нүд)
    public var offsetY: Double = 0         // face өндөртэй харьцангуй
    public var bounce: Double = 0          // face өндөртэй харьцангуй далайц
    public var bounceSpeed: Double = 0     // rad/s
    public var rightEyeScale: Double = 1   // confused-д тэгш бус
    public var rightEyeLift: Double = 0
    public var glow: Double = 1            // glow multiplier
    public var brightness: Double = 1      // 1 = normal
    public var semanticColor: UInt32? = nil // ARGB. nil бол theme өнгө
    public var overlay: FaceOverlay = []

    public init() {}

    public static func lerp(_ a: FaceParameters, _ b: FaceParameters, _ t: Double) -> FaceParameters {
        let t = min(max(t, 0), 1)
        func l(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        var r = FaceParameters()
        r.eyeWidth = l(a.eyeWidth, b.eyeWidth)
        r.eyeHeight = l(a.eyeHeight, b.eyeHeight)
        r.lidTop = l(a.lidTop, b.lidTop)
        r.lidAngle = l(a.lidAngle, b.lidAngle)
        r.bottomCut = l(a.bottomCut, b.bottomCut)
        r.offsetY = l(a.offsetY, b.offsetY)
        r.bounce = l(a.bounce, b.bounce)
        r.bounceSpeed = l(a.bounceSpeed, b.bounceSpeed)
        r.rightEyeScale = l(a.rightEyeScale, b.rightEyeScale)
        r.rightEyeLift = l(a.rightEyeLift, b.rightEyeLift)
        r.glow = l(a.glow, b.glow)
        r.brightness = l(a.brightness, b.brightness)
        r.semanticColor = t < 0.5 ? a.semanticColor : b.semanticColor
        r.overlay = t < 0.5 ? a.overlay : b.overlay
        return r
    }
}

public enum FaceLibrary {
    public static let red: UInt32 = 0xFFFF_3B4A
    public static let amber: UInt32 = 0xFFFF_B020
    public static let green: UInt32 = 0xFF34_D399

    public static let neutral = FaceParameters()

    private static func neutral(_ edit: (inout FaceParameters) -> Void) -> FaceParameters {
        var p = neutral
        edit(&p)
        return p
    }

    public static func parameters(for e: RobotExpression) -> FaceParameters {
        switch e {
        case .idle:
            neutral
        case .happy:
            neutral { $0.eyeWidth = 1.05; $0.eyeHeight = 0.95; $0.bottomCut = 0.55; $0.offsetY = -0.04; $0.bounce = 0.035; $0.bounceSpeed = 3; $0.glow = 1.2; $0.brightness = 1.12 }
        case .excited:
            neutral { $0.eyeWidth = 1.18; $0.eyeHeight = 1.15; $0.bottomCut = 0.35; $0.offsetY = -0.05; $0.bounce = 0.09; $0.bounceSpeed = 8; $0.glow = 1.45; $0.brightness = 1.25; $0.overlay = .sparkles }
        case .sad:
            neutral { $0.eyeWidth = 0.95; $0.eyeHeight = 0.82; $0.lidTop = 0.32; $0.lidAngle = -18; $0.offsetY = 0.1; $0.glow = 0.55; $0.brightness = 0.62 }
        case .confused:
            neutral { $0.lidTop = 0.08; $0.rightEyeScale = 0.7; $0.rightEyeLift = -0.1; $0.overlay = .question }
        case .angry:
            neutral { $0.eyeHeight = 0.88; $0.lidTop = 0.4; $0.lidAngle = 24; $0.glow = 1.35; $0.semanticColor = red }
        case .sleepy:
            neutral { $0.eyeWidth = 1.05; $0.eyeHeight = 0.9; $0.lidTop = 0.62; $0.lidAngle = -4; $0.offsetY = 0.06; $0.glow = 0.45; $0.brightness = 0.55; $0.overlay = .zzz }
        case .surprised:
            neutral { $0.eyeWidth = 1.22; $0.eyeHeight = 1.25; $0.glow = 1.6; $0.brightness = 1.3 }
        case .processing:
            neutral { $0.eyeWidth = 0.95; $0.eyeHeight = 1; $0.overlay = .ring }
        case .listening:
            neutral { $0.overlay = .wave; $0.glow = 1.15 }
        case .error:
            neutral { $0.glow = 1.25; $0.semanticColor = red; $0.overlay = [.pixelX, .warning] }
        case .newMessage:
            neutral { $0.eyeWidth = 1.05; $0.eyeHeight = 1.05; $0.bounce = 0.03; $0.bounceSpeed = 6; $0.glow = 1.2; $0.overlay = .bubble }
        case .reminder:
            neutral { $0.eyeWidth = 1.05; $0.offsetY = -0.03; $0.bounce = 0.03; $0.bounceSpeed = 4; $0.glow = 1.2; $0.overlay = .clock }
        case .lowBattery:
            neutral { $0.lidTop = 0.25; $0.lidAngle = -6; $0.glow = 0.8; $0.brightness = 0.85; $0.semanticColor = amber; $0.overlay = .battery }
        case .music:
            neutral { $0.bottomCut = 0.42; $0.bounce = 0.045; $0.bounceSpeed = 8.5; $0.glow = 1.2; $0.brightness = 1.1; $0.overlay = .notes }
        case .copied:
            // Happy-тэй ойролцоо ∩ нүд + ногоон ✓ (macOS-only, C#-д байхгүй).
            neutral { $0.eyeWidth = 1.05; $0.eyeHeight = 0.95; $0.bottomCut = 0.5; $0.offsetY = -0.03; $0.glow = 1.3; $0.brightness = 1.15; $0.overlay = .check }
        }
    }
}
