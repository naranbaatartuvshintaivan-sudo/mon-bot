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
    /// Тасралтгүй хөдөлдөг theme (Matrix бороо) — үргэлж дор хаяж 30fps (gentle).
    public var continuousTheme = false

    public init(followCursor: Bool = true, reducedMotion: Bool = false, blinkFrequency: Double = 1,
                animationSpeed: Double = 1, glitchTheme: Bool = false, continuousTheme: Bool = false) {
        self.followCursor = followCursor
        self.reducedMotion = reducedMotion
        self.blinkFrequency = blinkFrequency
        self.animationSpeed = animationSpeed
        self.glitchTheme = glitchTheme
        self.continuousTheme = continuousTheme
    }
}

/// Render хурдны хэрэгцээ. Нүд тайван үед бүтэн fps-ээр зурах шаардлагагүй (CPU).
public enum FaceFrameDemand: Int, Comparable, Sendable {
    /// Тайван: breathing л үлдсэн (0.022 далайц) → 10Hz хангалттай.
    case idle
    /// Удаан хөвөх overlay (zzz, ♪) → 20Hz.
    case ambient
    /// Өөрөө эргэн тойрноо харах (idle wander) — хэрэглэгчийн оролтгүй, удаан хөдөлгөөн → 30fps.
    case gentle
    /// Шилжилт, анивчилт, cursor дагах, хурдан overlay → бүтэн fps.
    case active

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    /// Frame хоорондын хугацаа. nil = дэлгэцийн refresh (performance mode-д 30fps).
    public func interval(performanceMode: Bool) -> Double? {
        switch self {
        case .idle: 1.0 / 10
        case .ambient: 1.0 / 20
        case .gentle: 1.0 / 30
        case .active: performanceMode ? 1.0 / 30 : nil
        }
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
    /// Харц "зогссон" гэж тооцох зай (normalized look; ≈0.2pt — нүдэнд үл ялгагдана, үлдсэнийг idle 10Hz гүйцээнэ).
    public static let lookSettle = 0.02
    public static let noticeSettle = 0.005
    /// 10Hz-ийн frame-ийг ч бүтэн тооцохын тулд (C# 0.05 нь 60fps-д зориулсан).
    public static let maxIdleFrameDt = 0.15
    /// Удаан хөдөлдөг overlay-ууд (ambient 20Hz-д гөлгөр харагдана).
    public static let slowOverlays: FaceOverlay = [.zzz, .notes]

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
    /// `maxDt` — бага fps-ээр (idle 10Hz) зурах үед цаг удаашрахгүйн тулд том clamp өгнө.
    public mutating func step(rawDt: Double, maxDt: Double = FaceAnimator.maxFrameDt) {
        guard rawDt > 0 else { return }
        let dt = min(rawDt, maxDt) * settings.animationSpeed
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

        // Cursor хөдлөхгүй бол өөрөө эргэн тойрноо харна — "амьд" мэдрэмж
        if isWandering, time >= nextIdleAction {
            idleLook = SIMD2((random() * 2 - 1) * 0.75, (random() * 2 - 1) * 0.4)
            idleLookUntil = time + 1.0 + random() * 1.2
            nextIdleAction = time + 4 + random() * 8
            if random() < 0.35 { blink.pullForward(to: time + 0.3) }
        }
        let target = lookTarget
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

    private var isWandering: Bool {
        let cursorFresh = cursor != nil && time - lastCursorMove < Self.cursorFreshSeconds
        return !cursorFresh || !settings.followCursor
    }

    /// Одоогийн оролтоор харах ёстой чиглэл (reduced motion-ий scale орсон).
    public var lookTarget: SIMD2<Double> {
        var target = SIMD2<Double>.zero
        if settings.followCursor, let c = cursor { target = Self.lookAt(c) }
        if isWandering && time < idleLookUntil { target = idleLook }
        if expression == .newMessage { target = SIMD2(0.85, -0.6) }
        else if expression == .sleepy { target = SIMD2(0, 0.35) }
        if let g = glanceTarget, time < glanceUntil { target = Self.lookAt(g) }
        if settings.reducedMotion { target *= Self.reducedLookScale }
        return target
    }

    /// Энэ төлөвт ямар хурдаар зурах хэрэгтэй вэ.
    public var frameDemand: FaceFrameDemand {
        if transT < 1 || blink.isBlinking || clickPulse > 0 || isGlitching { return .active }
        if abs(notice - (isCursorNear ? 1 : 0)) > Self.noticeSettle { return .active }
        // Ойрын event-ийг idle frame-ийн хооронд алдахгүйн тулд урьдчилан шилжинэ.
        let soon = Self.maxIdleFrameDt
        if BlinkScheduler.canBlink(expression) && blink.nextBlink - time < soon { return .active }
        if settings.glitchTheme && !settings.reducedMotion && nextGlitch - time < soon { return .active }
        let p = to
        if p.bounce > 0.001 && !settings.reducedMotion { return .active }
        if !p.overlay.isEmpty && !Self.slowOverlays.isSuperset(of: p.overlay) { return .active }

        var demand: FaceFrameDemand = p.overlay.isEmpty ? .idle : .ambient
        // Matrix бороо — тасралтгүй, гэхдээ хэрэглэгчийн оролтоос биш → 30fps.
        if settings.continuousTheme { demand = .gentle }
        let d = look - lookTarget
        let lookMoving = (d * d).sum().squareRoot() > Self.lookSettle
        if lookMoving { demand = max(demand, isSelfDrivenLook ? .gentle : .active) }
        if isWandering && nextIdleAction - time < soon { demand = max(demand, .gentle) }
        return demand
    }

    /// Харц хэрэглэгчийн оролтоос биш, robot өөрөө (idle wander эсвэл түүнээс буцах) хөдөлж байна.
    /// Click glance болон expression-ийн харц (NewMessage, Sleepy) нь шилжилт тул бүтэн fps.
    var isSelfDrivenLook: Bool {
        guard isWandering else { return false }
        if glanceTarget != nil && time < glanceUntil { return false }
        return expression != .newMessage && expression != .sleepy
    }

    static func lookAt(_ p: SIMD2<Double>) -> SIMD2<Double> {
        let v = EyeMath.lookVector(dx: p.x, dy: p.y, range: lookRange)
        return SIMD2(v.x, v.y)
    }
}
