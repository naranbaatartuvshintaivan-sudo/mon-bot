import Foundation
import Testing
@testable import DeskBotCore

// C# порт: tests/DeskBot.Core.Tests/ExpressionStateMachineTests.cs

/// 2026-11-18 09:00 +08:00 (C# T0-тэй ижил)
let T0: Date = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
    return cal.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 9))!
}()

@Suite struct ExpressionStateMachineTests {
    @Test func defaultsToIdle() {
        #expect(ExpressionStateMachine().current == .idle)
    }

    @Test func higherPriorityWinsImmediately() {
        let sm = ExpressionStateMachine()
        sm.set(.music, .music, now: T0)
        sm.set(.error, .error, now: T0)
        #expect(sm.current == .error)
    }

    @Test func lowerPriorityDoesNotOverride() {
        let sm = ExpressionStateMachine()
        sm.set(.reminder, .reminder, now: T0)
        sm.set(.music, .music, now: T0)
        #expect(sm.current == .reminder)
    }

    @Test func timedLayerExpiresOnTickAndFallsBack() {
        let sm = ExpressionStateMachine()
        sm.set(.music, .music, now: T0)
        sm.set(.userClick, .surprised, now: T0, duration: 0.4)
        #expect(sm.current == .surprised)

        sm.tick(now: T0.addingTimeInterval(0.5))
        #expect(sm.current == .music)
    }

    @Test func downgradeIsHeldForMinHoldToPreventFlicker() {
        let sm = ExpressionStateMachine()
        sm.minHold = 0.3
        sm.set(.userClick, .surprised, now: T0)
        sm.clear(.userClick, now: T0.addingTimeInterval(0.05))
        #expect(sm.current == .surprised) // хараахан бууж болохгүй

        sm.tick(now: T0.addingTimeInterval(0.4))
        #expect(sm.current == .idle)
    }

    @Test func angryCanNeverBeBaseMood() {
        let sm = ExpressionStateMachine()
        sm.setBaseMood(.angry, now: T0)
        #expect(sm.current == .idle)

        sm.setBaseMood(.happy, now: T0)
        #expect(sm.current == .happy)
    }

    @Test func changedEventFiresOnlyOnRealChange() {
        let sm = ExpressionStateMachine()
        var count = 0
        sm.onChange = { _ in count += 1 }
        sm.set(.music, .music, now: T0)
        sm.set(.music, .music, now: T0)
        #expect(count == 1)
    }

    @Test func baseMoodReturnsAfterAllLayersCleared() {
        let sm = ExpressionStateMachine()
        sm.minHold = 0
        sm.setBaseMood(.happy, now: T0)
        sm.set(.error, .error, now: T0)
        sm.clear(.error, now: T0.addingTimeInterval(1))
        #expect(sm.current == .happy)
    }
}

@Suite struct EyeMathTests {
    @Test func lookVectorIsBounded() {
        let (x, y) = EyeMath.lookVector(dx: 5000, dy: 5000, range: 400)
        let m = (x * x + y * y).squareRoot()
        #expect(m >= 0.99 && m <= 1.0001)
    }

    @Test func lookVectorZeroAtCenter() {
        let v = EyeMath.lookVector(dx: 0, dy: 0, range: 400)
        #expect(v.x == 0 && v.y == 0)
    }

    @Test func smoothFactorIsFrameRateIndependent() {
        // 2 × 8ms алхам == 1 × 16ms алхам
        let a = EyeMath.smoothFactor(dt: 0.008, rate: 10)
        let two = 1 - (1 - a) * (1 - a)
        #expect(abs(EyeMath.smoothFactor(dt: 0.016, rate: 10) - two) < 1e-6)
    }

    @Test func blinkClosesInTheMiddle() {
        #expect(EyeMath.blinkOpenness(0) == 1)
        #expect(EyeMath.blinkOpenness(0.5) < 0.1)
    }

    @Test func faceLerpEndpoints() {
        let a = FaceLibrary.parameters(for: .idle)
        let b = FaceLibrary.parameters(for: .angry)
        #expect(FaceParameters.lerp(a, b, 0) == a)
        #expect(FaceParameters.lerp(a, b, 1) == b)
    }

    @Test(arguments: RobotExpression.allCases)
    func everyExpressionHasParameters(_ e: RobotExpression) {
        #expect(FaceLibrary.parameters(for: e).eyeWidth > 0)
    }
}
