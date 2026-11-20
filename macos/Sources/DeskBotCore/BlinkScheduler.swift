// C# порт: src/DeskBot.App/UI/Controls/RobotFace.cs — Update() доторх анивчилт + ScheduleBlink().
// WPF control-оос салгаж цэвэр struct болгосон (тест хийхийн тулд). Тоонууд C#-тай ЯГ ижил.

/// Нүд анивчих хуваарь. `update` frame бүр дуудагдаж `openness`-ийг (1 = нээлттэй) шинэчилнэ.
public struct BlinkScheduler: Sendable {
    public static let duration = 0.16
    public static let doubleBlinkChance = 0.12
    public static let doubleBlinkDelay = 0.18
    public static let minInterval = 2.4
    public static let intervalSpread = 3.6
    public static let sleepyMultiplier = 1.8

    public private(set) var openness = 1.0
    /// < 0 бол анивчаагүй байна.
    public private(set) var blinkStart = -1.0
    public private(set) var nextBlink = 1.5

    public init() {}

    public var isBlinking: Bool { blinkStart >= 0 }

    /// Processing / Error / Listening үед анивчихгүй (overlay нүд).
    public static func canBlink(_ e: RobotExpression) -> Bool {
        switch e {
        case .processing, .error, .listening: false
        default: true
        }
    }

    /// Дараагийн анивчилт хүртэлх хугацаа. `r1` < 0.12 бол давхар анивчилт (0.18с).
    public static func interval(r1: Double, r2: Double, sleepy: Bool, frequency: Double) -> Double {
        if r1 < doubleBlinkChance { return doubleBlinkDelay }
        let mult = sleepy ? sleepyMultiplier : 1.0
        return (minInterval + r2 * intervalSpread) * mult / frequency
    }

    public mutating func update(time: Double, canBlink: Bool, sleepy: Bool, frequency: Double,
                                random: () -> Double) {
        if blinkStart < 0 && canBlink && time >= nextBlink { blinkStart = time }
        openness = 1
        guard blinkStart >= 0 else { return }
        let phase = (time - blinkStart) / Self.duration
        if phase >= 1 {
            blinkStart = -1
            let r1 = random()
            let r2 = r1 < Self.doubleBlinkChance ? 0 : random() // C#: давхар бол 2 дахь NextDouble дуудагдахгүй
            nextBlink = time + Self.interval(r1: r1, r2: r2, sleepy: sleepy, frequency: frequency)
        } else {
            openness = EyeMath.blinkOpenness(phase)
        }
    }

    /// Шууд анивчуулна (notice).
    public mutating func trigger(at time: Double) { blinkStart = time }

    /// Дараагийн анивчилтыг хамгийн оройтвол `time` болгоно (idle wander-ийн 35%).
    public mutating func pullForward(to time: Double) { nextBlink = min(nextBlink, time) }
}
