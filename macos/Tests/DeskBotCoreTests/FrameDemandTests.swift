import Testing
@testable import DeskBotCore

/// CPU: нүд тайван үед бүтэн fps-ээр зурахгүй (FaceAnimator.frameDemand).
@Suite struct FrameDemandTests {
    /// random = 0.5 → анхны blink 1.5с, idle wander 6с-д.
    private func animator(_ settings: FaceAnimatorSettings = .init()) -> FaceAnimator {
        FaceAnimator(settings: settings, random: { 0.5 })
    }
    private func run(_ a: inout FaceAnimator, seconds: Double, fps: Double = 60) {
        for _ in 0..<Int(seconds * fps) { a.step(rawDt: 1 / fps, maxDt: FaceAnimator.maxIdleFrameDt) }
    }

    @Test func calmIdleIsIdle() {
        var a = animator()
        #expect(a.frameDemand == .idle)
        run(&a, seconds: 1)
        #expect(a.frameDemand == .idle)
    }

    @Test func transitionAndClickAreActive() {
        var a = animator()
        a.setExpression(.surprised)
        #expect(a.frameDemand == .active)
        run(&a, seconds: 1)
        #expect(a.frameDemand == .idle) // Surprised: overlay/bounce-гүй
        a.pulse()
        #expect(a.frameDemand == .active)
    }

    @Test func upcomingBlinkWakesBeforeItStarts() {
        var a = animator()
        run(&a, seconds: 1.3)
        #expect(a.frameDemand == .idle)
        run(&a, seconds: 0.1)                  // t≈1.4, blink 1.5-д
        #expect(a.frameDemand == .active)
        run(&a, seconds: 0.4)                  // blink дууссан
        #expect(!a.blink.isBlinking)
        #expect(a.frameDemand == .idle)
    }

    @Test func cursorMoveIsActiveUntilEyesSettle() {
        var a = animator()
        a.setCursor(dx: 300, dy: 0)
        #expect(a.frameDemand == .active)
        run(&a, seconds: 1.2)
        #expect(a.frameDemand == .idle)       // харц зорилтдоо хүрсэн, blink-ээс өмнө
    }

    @Test func overlaysPickRate() {
        var a = animator()
        a.setExpression(.sleepy)               // zzz — удаан
        run(&a, seconds: 0.5)
        #expect(a.frameDemand == .ambient)
        a.setExpression(.processing)           // эргэдэг ring
        run(&a, seconds: 0.5)
        #expect(a.frameDemand == .active)
        a.setExpression(.music)                // ♪ ч гэсэн bounce → бүтэн fps
        run(&a, seconds: 0.5)
        #expect(a.frameDemand == .active)
    }

    @Test func matrixThemeAlwaysActive() {
        let a = animator(FaceAnimatorSettings(continuousTheme: true))
        #expect(a.frameDemand == .active)
    }

    @Test func lowFrameRateKeepsRealTime() {
        var a = animator()
        run(&a, seconds: 3, fps: 10)
        #expect(abs(a.time - 3) < 1e-9)       // 10Hz-д цаг удаашрахгүй (0.05 clamp биш)
        var b = animator()
        b.step(rawDt: 5)                       // pause-ийн дараах том dt → clamp хэвээр
        #expect(b.time == FaceAnimator.maxFrameDt)
    }

    @Test func intervals() {
        #expect(FaceFrameDemand.idle.interval(performanceMode: false) == 0.1)
        #expect(FaceFrameDemand.ambient.interval(performanceMode: false) == 0.05)
        #expect(FaceFrameDemand.active.interval(performanceMode: false) == nil)
        #expect(FaceFrameDemand.active.interval(performanceMode: true) == 1.0 / 30)
    }
}
