// C# порт: src/DeskBot.App/UI/Controls/RobotFace.cs — Expression setter, SetCursorScreen, Glance, Pulse,
// OnRendering (dt clamp), Update(). Render-ээс салгасан цэвэр төлөв → тест хийж болно.
// Координат: face төвөөс хэмжсэн point, y ДООШОО (WPF / SwiftUI Canvas-тай ижил).

/// Face animation-д нөлөөлөх тохиргоо (AppSettings-ийн хэсэг).
public struct FaceAnimatorSettings: Equatable, Sendable {
    public var followCursor = true
    public var reducedMotion = false
    public var blinkFrequency = 1.0
    public var animationSpeed = 1.0
    /// Glitch theme — RGB split burst хуваарь ажиллана.
    public var glitchTheme = false

    public init(followCursor: Bool = true, reducedMotion: Bool = false, blinkFrequency: Double = 1,
                animationSpeed: Double = 1, glitchTheme: Bool = false) {
        self.followCursor = followCursor
        self.reducedMotion = reducedMotion
        self.blinkFrequency = blinkFrequency
        self.animationSpeed = animationSpeed
        self.glitchTheme = glitchTheme
    }
}

public struct FaceAnimator {
    public static let transitionSeconds = 0.24
    public static let maxFrameDt = 0.05
    public static let lookRate = 7.5
    public static let reducedLookRate = 14.0
    public static let reducedLookScale = 0.6
    public static let lookRange = 420.0
    public static let noticeRadius = 170.0
    public static let noticeRate = 6.0
    public static let cursorFreshSeconds = 8.0
    public static let clickPulseDecay = 2.8

    public var settings: FaceAnimatorSettings
    private let random: () -> Double

    // Expression transition
    public private(set) var expression: RobotExpression = .idle
    public private(set) var from = FaceLibrary.parameters(for: .idle)
    public private(set) var to = FaceLibrary.parameters(for: .idle)
    public private(set) var transT = 1.0

    // Харц
    public private(set) var cursor: SIMD2<Double>?
    private var lastCursorMove = -100.0
    public private(set) var look = SIMD2<Double>.zero
    private var glanceTarget: SIMD2<Double>?
    private var glanceUntil = 0.0
    private var idleLook = SIMD2<Double>.zero
    private var idleLookUntil = 0.0
    private var nextIdleAction = 6.0

    // Цаг, анивчилт, pulse
    public private(set) var time = 0.0
    public private(set) var frame = 0
    public private(set) var blink = BlinkScheduler()
    public private(set) var notice = 0.0
    public private(set) var clickPulse = 0.0
    private var glitchUntil = 0.0
    private var nextGlitch = 3.0

    public init(settings: FaceAnimatorSettings = .init(),
                random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.settings = settings
        self.random = random
    }

    // MARK: - Inputs

    public mutating func setExpression(_ value: RobotExpression) {
        guard value != expression else { return }
        from = FaceParameters.lerp(from, to, EyeMath.easeOutCubic(transT)) // дундаас нь эхэлнэ — үсрэлтгүй
        to = FaceLibrary.parameters(for: value)
        expression = value
        transT = 0
    }

    /// Cursor-ийн байрлал face төвөөс (y доошоо, point).
    public mutating func setCursor(dx: Double, dy: Double) {
        let p = SIMD2(dx, dy)
        if let old = cursor {
            let d = old - p
            if (d * d).sum() < 0.25 { return }
        }
        cursor = p
        lastCursorMove = time
    }

    /// Хаа нэгтээ click хийхэд тэр зүг рүү богино харна.
    public mutating func glance(dx: Double, dy: Double, seconds: Double = 0.7) {
        glanceTarget = SIMD2(dx, dy)
        glanceUntil = time + seconds
    }

    /// Robot дээр click — нүд түр томорно.
    public mutating func pulse() { clickPulse = 1 }

    // MARK: - Outputs

    public var easedT: Double { EyeMath.easeOutCubic(transT) }
    public var currentParameters: FaceParameters { FaceParameters.lerp(from, to, easedT) }
    public var blinkOpenness: Double { blink.openness }
    public var isGlitching: Bool { settings.glitchTheme && time < glitchUntil }

    /// Cursor face төвөөс `noticeRadius` дотор байна уу (Cursor layer-д ашиглана).
    public var isCursorNear: Bool {
        guard let c = cursor else { return false }
        return (c * c).sum().squareRoot() < Self.noticeRadius
    }

    // MARK: - Frame

    /// Render frame бүрийн бодит dt (секунд). C#: min(dt, 0.05) × AnimationSpeed.
    public mutating func step(rawDt: Double) {
        guard rawDt > 0 else { return }
        let dt = min(rawDt, Self.maxFrameDt) * settings.animationSpeed
        time += dt
        frame += 1
        update(dt: dt)
    }

    private mutating func update(dt: Double) {
        let reduced = settings.reducedMotion
        transT = min(1, transT + dt / Self.transitionSeconds * (reduced ? 2 : 1))

        // Анивчилт
        let canBlink = BlinkScheduler.canBlink(expression)
        blink.update(time: time, canBlink: canBlink, sleepy: expression == .sleepy,
                     frequency: settings.blinkFrequency, random: random)

        // Харах чиглэл
        var target = SIMD2<Double>.zero
        let cursorFresh = cursor != nil && time - lastCursorMove < Self.cursorFreshSeconds

        if settings.followCursor, let c = cursor { target = Self.lookAt(c) }

        if !cursorFresh || !settings.followCursor {
            // Cursor хөдлөхгүй бол өөрөө эргэн тойрноо харна — "амьд" мэдрэмж
            if time >= nextIdleAction {
                idleLook = SIMD2((random() * 2 - 1) * 0.75, (random() * 2 - 1) * 0.4)
                idleLookUntil = time + 1.0 + random() * 1.2
                nextIdleAction = time + 4 + random() * 8
                if random() < 0.35 { blink.pullForward(to: time + 0.3) }
            }
            if time < idleLookUntil { target = idleLook }
        }

        if expression == .newMessage { target = SIMD2(0.85, -0.6) }
        else if expression == .sleepy { target = SIMD2(0, 0.35) }
        if let g = glanceTarget, time < glanceUntil { target = Self.lookAt(g) }

        if reduced { target *= Self.reducedLookScale }
        look = EyeMath.smoothToward(look, target, dt: dt, rate: reduced ? Self.reducedLookRate : Self.lookRate)

        // Notice — cursor ойртоход нүд томорч, гэрэлтэнэ, нэг анивчина
        let near = isCursorNear ? 1.0 : 0.0
        let prev = notice
        notice += (near - notice) * EyeMath.smoothFactor(dt: dt, rate: Self.noticeRate)
        if prev < 0.5 && notice >= 0.5 && !blink.isBlinking && canBlink { blink.trigger(at: time) }

        clickPulse = max(0, clickPulse - dt * Self.clickPulseDecay)

        if settings.glitchTheme && !reduced && time >= nextGlitch {
            glitchUntil = time + 0.14 + random() * 0.14
            nextGlitch = time + 2 + random() * 4
        }
    }

    static func lookAt(_ p: SIMD2<Double>) -> SIMD2<Double> {
        let v = EyeMath.lookVector(dx: p.x, dy: p.y, range: lookRange)
        return SIMD2(v.x, v.y)
    }
}
