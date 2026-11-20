import Foundation

// C# порт: src/DeskBot.Core/Expressions/EyeMath.cs

public enum EyeMath {
    /// Face төвөөс cursor руу чиглэсэн, -1..1 хүрээнд хязгаарлагдсан харах вектор.
    /// range-ээс хол бол бүрэн хазайна, ойр бол бага хазайна (байгалийн).
    public static func lookVector(dx: Double, dy: Double, range: Double) -> (x: Double, y: Double) {
        let d = (dx * dx + dy * dy).squareRoot()
        if d < 1e-6 || range <= 0 { return (0, 0) }
        var mag = min(1.0, d / range)
        // Ease — ойрхон үед мэдрэмж өндөр, хол үед аажмаар saturate
        mag = 1 - (1 - mag) * (1 - mag)
        return (dx / d * mag, dy / d * mag)
    }

    /// Frame-rate-аас хамааралгүй exponential smoothing коэффициент.
    public static func smoothFactor(dt: Double, rate: Double) -> Double {
        dt <= 0 ? 0 : 1 - exp(-rate * dt)
    }

    /// `current`-ийг `target` руу frame-rate-аас хамааралгүй ойртуулна: current += (target − current)·(1 − e^(−rate·dt)).
    public static func smoothToward(_ current: SIMD2<Double>, _ target: SIMD2<Double>,
                                    dt: Double, rate: Double) -> SIMD2<Double> {
        current + (target - current) * smoothFactor(dt: dt, rate: rate)
    }

    public static func easeOutCubic(_ t: Double) -> Double {
        let u = 1 - min(max(t, 0), 1)
        return 1 - u * u * u
    }

    /// Нүд анивчих openness (1 = нээлттэй). phase 0..1.
    public static func blinkOpenness(_ phase: Double) -> Double {
        if phase <= 0 || phase >= 1 { return 1 }
        return 1 - sin(Double.pi * phase) * 0.92
    }
}
