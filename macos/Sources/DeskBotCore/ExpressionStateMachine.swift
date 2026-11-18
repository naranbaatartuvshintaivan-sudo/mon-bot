import Foundation

// C# порт: src/DeskBot.Core/Expressions/ExpressionStateMachine.cs

/// Олон эх үүсвэрээс ирэх expression хүсэлтийг priority-оор шийдвэрлэнэ.
/// - Өндөр priority шууд ялна.
/// - Бага priority руу буухдаа `minHold` хугацаа өнгөрөхийг хүлээнэ (анивчилт үүсгэхгүй).
/// - Хугацаатай layer-ууд `tick` дээр дуусна.
/// Thread-safe биш — main thread дээр ашиглана.
public final class ExpressionStateMachine {
    private struct Layer {
        let expression: RobotExpression
        let until: Date?
    }

    private var layers: [ExpressionSource: Layer] = [:]
    private var currentPriority = 0
    private var lastChange = Date.distantPast

    public var minHold: TimeInterval = 0.25
    public private(set) var current: RobotExpression = .idle
    public private(set) var baseMood: RobotExpression = .idle

    /// Expression бодитоор солигдох үед дуудагдана.
    public var onChange: ((RobotExpression) -> Void)?

    public init() {}

    public func setBaseMood(_ mood: RobotExpression, now: Date) {
        baseMood = ExpressionRules.sanitizeBaseMood(mood)
        evaluate(now: now, force: true)
    }

    public func set(_ source: ExpressionSource, _ expression: RobotExpression, now: Date, duration: TimeInterval? = nil) {
        layers[source] = Layer(expression: expression, until: duration.map { now.addingTimeInterval($0) })
        evaluate(now: now)
    }

    public func clear(_ source: ExpressionSource, now: Date) {
        if layers.removeValue(forKey: source) != nil {
            evaluate(now: now)
        }
    }

    public func isActive(_ source: ExpressionSource) -> Bool { layers[source] != nil }

    /// Хугацаа дууссан layer-уудыг цэвэрлэж, хойшлогдсон шилжилтийг хийнэ.
    public func tick(now: Date) {
        layers = layers.filter { _, layer in
            guard let u = layer.until else { return true }
            return u > now
        }
        evaluate(now: now)
    }

    private func evaluate(now: Date, force: Bool = false) {
        let (next, priority) = resolve(now: now)
        if next == current && priority == currentPriority { return }

        // Доод priority руу буухдаа хэт хурдан солигдохоос сэргийлнэ
        if !force && priority < currentPriority && now.timeIntervalSince(lastChange) < minHold {
            return
        }

        let changed = next != current
        current = next
        currentPriority = priority
        if changed {
            lastChange = now
            onChange?(next)
        }
    }

    private func resolve(now: Date) -> (RobotExpression, Int) {
        var best = baseMood
        var bestPriority = 0
        for (src, layer) in layers {
            if let u = layer.until, u <= now { continue }
            if src.priority > bestPriority {
                bestPriority = src.priority
                best = layer.expression
            }
        }
        return (best, bestPriority)
    }
}
