import CoreGraphics
import Foundation
import Testing
@testable import DeskBotCore

// M2: RobotFace.cs-ийн логик (look smoothing, blink scheduler, transition, notice, layout, өнгө).

/// Deterministic random: өгсөн дарааллаар эргэлдэнэ.
final class FixedRandom: @unchecked Sendable {
    private let values: [Double]
    private var i = 0
    init(_ values: [Double]) { self.values = values }
    func next() -> Double { defer { i += 1 }; return values[i % values.count] }
}

private func approx(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool { abs(a - b) <= eps }

@Suite struct LookSmoothingTests {
    @Test func frameRateIndependent() {
        let target = SIMD2(0.8, -0.3)
        func run(fps: Int) -> SIMD2<Double> {
            var v = SIMD2<Double>.zero
            for _ in 0..<fps { v = EyeMath.smoothToward(v, target, dt: 1 / Double(fps), rate: 7.5) }
            return v
        }
        let a = run(fps: 30), b = run(fps: 60), c = run(fps: 144)
        #expect(approx(a.x, b.x) && approx(b.x, c.x))
        #expect(approx(a.y, b.y) && approx(b.y, c.y))
    }

    @Test func convergesExponentiallyWithRate7_5() {
        var v = SIMD2<Double>.zero
        for _ in 0..<60 { v = EyeMath.smoothToward(v, SIMD2(1, 0), dt: 1.0 / 60, rate: 7.5) }
        #expect(approx(1 - v.x, exp(-7.5)))   // 1с дараа үлдэгдэл = e^(−7.5)
    }

    @Test func zeroDtDoesNothing() {
        let v = EyeMath.smoothToward(SIMD2(0.2, 0.1), SIMD2(1, 1), dt: 0, rate: 7.5)
        #expect(v == SIMD2(0.2, 0.1))
    }

    @Test func animatorLooksTowardCursor() {
        var a = FaceAnimator(random: { 0.5 })
        a.setCursor(dx: 400, dy: 0)
        for _ in 0..<120 { a.step(rawDt: 1.0 / 60) }
        let expected = EyeMath.lookVector(dx: 400, dy: 0, range: FaceAnimator.lookRange)
        #expect(approx(a.look.x, expected.x, 1e-3))
        #expect(approx(a.look.y, 0, 1e-9))
    }

    @Test func reducedMotionScalesLook() {
        var a = FaceAnimator(settings: .init(reducedMotion: true), random: { 0.5 })
        a.setCursor(dx: 4000, dy: 0) // range-ээс хол → бүрэн хазайлт 1
        for _ in 0..<120 { a.step(rawDt: 1.0 / 60) }
        #expect(approx(a.look.x, 0.6, 1e-3))
    }

    @Test func idleWanderWhenCursorStale() {
        var a = FaceAnimator(random: { 0.9 })
        // Cursor байхгүй → 6с-д анхны idle харц (0.9·2−1)·0.75 = 0.6
        for _ in 0..<(60 * 7) { a.step(rawDt: 1.0 / 60) }
        #expect(a.look.x > 0.3)
    }
}

@Suite struct BlinkSchedulerTests {
    @Test func opennessCurve() {
        #expect(EyeMath.blinkOpenness(0) == 1)
        #expect(approx(EyeMath.blinkOpenness(0.5), 0.08))
        #expect(EyeMath.blinkOpenness(1) == 1)
    }

    @Test func intervalMatchesCSharp() {
        #expect(BlinkScheduler.interval(r1: 0.05, r2: 0.9, sleepy: false, frequency: 1) == 0.18) // давхар
        #expect(approx(BlinkScheduler.interval(r1: 0.5, r2: 0, sleepy: false, frequency: 1), 2.4))
        #expect(approx(BlinkScheduler.interval(r1: 0.5, r2: 1, sleepy: false, frequency: 1), 6.0))
        #expect(approx(BlinkScheduler.interval(r1: 0.5, r2: 0, sleepy: true, frequency: 1), 2.4 * 1.8))
        #expect(approx(BlinkScheduler.interval(r1: 0.5, r2: 0, sleepy: false, frequency: 2), 1.2))
    }

    @Test func firstBlinkAt1_5sLasts0_16s() {
        var b = BlinkScheduler()
        let rnd = FixedRandom([0.5])
        var closedAt: [Double] = []
        var t = 0.0
        while t < 2 {
            b.update(time: t, canBlink: true, sleepy: false, frequency: 1, random: rnd.next)
            if b.openness < 1 { closedAt.append(t) }
            t += 0.01
        }
        #expect(closedAt.first.map { $0 >= 1.5 && $0 < 1.52 } == true)
        #expect(closedAt.last.map { $0 < 1.5 + 0.16 + 0.01 } == true)
        // 0.5 → interval 2.4 + 0.5·3.6 = 4.2
        #expect(b.nextBlink > 1.66 + 4.1 && b.nextBlink < 1.66 + 4.3)
    }

    @Test func doubleBlinkReschedulesIn0_18s() {
        var b = BlinkScheduler()
        let rnd = FixedRandom([0.05])
        var t = 1.5
        while b.isBlinking || t == 1.5 {
            b.update(time: t, canBlink: true, sleepy: false, frequency: 1, random: rnd.next)
            t += 0.01
        }
        #expect(approx(b.nextBlink - (t - 0.01), 0.18, 1e-9))
    }

    @Test func overlayExpressionsNeverBlink() {
        for e in [RobotExpression.processing, .error, .listening] {
            #expect(!BlinkScheduler.canBlink(e))
            var a = FaceAnimator(random: { 0.5 })
            a.setExpression(e)
            var minOpen = 1.0
            for _ in 0..<(60 * 20) { a.step(rawDt: 1.0 / 60); minOpen = min(minOpen, a.blinkOpenness) }
            #expect(minOpen == 1, "\(e) blinked")
        }
        #expect(BlinkScheduler.canBlink(.idle) && BlinkScheduler.canBlink(.sleepy))
    }

    @Test func pullForwardOnlyMovesEarlier() {
        var b = BlinkScheduler()
        b.pullForward(to: 5)
        #expect(b.nextBlink == 1.5)
        b.pullForward(to: 0.3)
        #expect(b.nextBlink == 0.3)
    }
}

@Suite struct FaceAnimatorTests {
    @Test func transitionCompletesIn0_24s() {
        var a = FaceAnimator(random: { 0.5 })
        a.setExpression(.happy)
        for _ in 0..<15 { a.step(rawDt: 1.0 / 60) } // 0.25с
        #expect(a.currentParameters == FaceLibrary.parameters(for: .happy))
    }

    @Test func switchingMidTransitionDoesNotJump() {
        var a = FaceAnimator(random: { 0.5 })
        a.setExpression(.surprised)
        for _ in 0..<6 { a.step(rawDt: 1.0 / 60) }
        let before = a.currentParameters
        a.setExpression(.sad)
        #expect(a.currentParameters == before) // шинэ transition яг одоогийн цэгээс эхэлнэ
    }

    @Test func dtIsClampedTo50ms() {
        var a = FaceAnimator(random: { 0.5 })
        a.step(rawDt: 2)
        #expect(approx(a.time, 0.05))
        var fast = FaceAnimator(settings: .init(animationSpeed: 2), random: { 0.5 })
        fast.step(rawDt: 0.01)
        #expect(approx(fast.time, 0.02))
    }

    @Test func noticeWhenCursorWithin170() {
        var a = FaceAnimator(random: { 0.5 })
        a.setCursor(dx: 300, dy: 0)
        #expect(!a.isCursorNear)
        for _ in 0..<60 { a.step(rawDt: 1.0 / 60) }
        #expect(a.notice < 0.01)

        a.setCursor(dx: 100, dy: 50)
        #expect(a.isCursorNear)
        var blinked = false
        for _ in 0..<60 {
            a.step(rawDt: 1.0 / 60)
            if a.blink.isBlinking { blinked = true }
        }
        #expect(a.notice > 0.99)
        #expect(blinked) // notice 0.5-г давахад нэг удаа анивчина
    }

    @Test func tinyCursorMovesIgnored() {
        var a = FaceAnimator(random: { 0.5 })
        a.setCursor(dx: 10, dy: 10)
        a.setCursor(dx: 10.3, dy: 10.3) // ∆² = 0.18 < 0.25
        #expect(a.cursor == SIMD2(10, 10))
    }

    @Test func sleepyAndNewMessageOverrideLook() {
        var a = FaceAnimator(random: { 0.5 })
        a.setCursor(dx: -400, dy: 0)
        a.setExpression(.newMessage)
        for _ in 0..<120 { a.step(rawDt: 1.0 / 60) }
        #expect(approx(a.look.x, 0.85, 1e-3) && approx(a.look.y, -0.6, 1e-3))
    }

    @Test func glitchOnlyWithGlitchTheme() {
        var a = FaceAnimator(random: { 0.5 })
        var b = FaceAnimator(settings: .init(glitchTheme: true), random: { 0.5 })
        var aGlitched = false, bGlitched = false
        for _ in 0..<(60 * 10) {
            a.step(rawDt: 1.0 / 60); b.step(rawDt: 1.0 / 60)
            aGlitched = aGlitched || a.isGlitching
            bGlitched = bGlitched || b.isGlitching
        }
        #expect(!aGlitched && bGlitched)
    }
}

@Suite struct FaceLayoutTests {
    private func layout(_ p: FaceParameters = .init(), size: CGSize = CGSize(width: 112, height: 32),
                        look: SIMD2<Double> = .zero, spacing: Double? = nil) -> FaceLayout {
        FaceLayout(size: size, params: p, shape: .rounded, eyeSize: 1, eyeSpacing: 1, look: look, time: 0,
                   notice: 0, clickPulse: 0, reducedMotion: false, performanceMode: false, spacingOverride: spacing)
    }

    @Test func baseSizesMatchCSharp() {
        let l = layout()
        #expect(approx(l.baseH, 32 * 0.62))
        #expect(approx(l.baseW, 32 * 0.62 * 0.8))
        #expect(approx(l.spacing, l.baseW * 1.95))
        #expect(approx(Double(l.left.center.x + l.right.center.x) / 2, 56))
    }

    @Test func spacingOverridePlacesEyesInNotchEars() {
        let l = layout(size: CGSize(width: 273, height: 37), spacing: 229)
        #expect(approx(Double(l.left.center.x), 136.5 - 114.5))
        #expect(approx(Double(l.right.center.x), 136.5 + 114.5))
    }

    @Test func lookShiftsEyes() {
        let l = layout(look: SIMD2(1, 0))
        #expect(approx(Double(l.center.x), 56 + l.baseW * 0.6))
    }

    @Test func lidCutsTopAndAngryIsMirrored() {
        let c = CGPoint(x: 50, y: 50)
        let plain = FaceGeometry.eyePath(center: c, width: 20, height: 30, cornerRadius: 5,
                                         lidTop: 0, lidAngle: 0, bottomCut: 0, side: -1).boundingBoxOfPath
        #expect(approx(Double(plain.minY), 35, 1e-6) && approx(Double(plain.height), 30, 1e-6))

        let lid = FaceGeometry.eyePath(center: c, width: 20, height: 30, cornerRadius: 5,
                                       lidTop: 0.4, lidAngle: 0, bottomCut: 0, side: -1).boundingBoxOfPath
        #expect(approx(Double(lid.minY), 35 + 12, 1e-3))

        // Angry (+24°): дотор тал доош → зүүн нүдний баруун (дотор) дээд булан доогуур
        let leftEye = FaceGeometry.eyePath(center: c, width: 20, height: 30, cornerRadius: 0,
                                           lidTop: 0.4, lidAngle: 24, bottomCut: 0, side: -1)
        #expect(leftEye.contains(CGPoint(x: 41, y: 46)))   // гадна тал — нээлттэй
        #expect(!leftEye.contains(CGPoint(x: 59, y: 50)))  // дотор тал — lid хучсан
        let rightEye = FaceGeometry.eyePath(center: c, width: 20, height: 30, cornerRadius: 0,
                                            lidTop: 0.4, lidAngle: 24, bottomCut: 0, side: 1)
        #expect(rightEye.contains(CGPoint(x: 59, y: 46)))
        #expect(!rightEye.contains(CGPoint(x: 41, y: 50)))
    }

    @Test func bottomCutMakesHappyArch() {
        let c = CGPoint(x: 50, y: 50)
        let happy = FaceGeometry.eyePath(center: c, width: 20, height: 30, cornerRadius: 5,
                                         lidTop: 0, lidAngle: 0, bottomCut: 0.55, side: -1)
        #expect(!happy.contains(c))                          // төв хэсэг тайрагдсан (∩)
        #expect(happy.contains(CGPoint(x: 50, y: 37)))       // дээд нум үлдсэн
    }
}

@Suite struct FaceColorTests {
    @Test func mixUsesBankersRoundingLikeCSharp() {
        // 0 + (255−0)·0.5 = 127.5 → Math.Round → 128 (тэгш)
        #expect(RGBA.mix(RGBA(r: 0, g: 0, b: 0), RGBA(r: 255, g: 255, b: 255), 0.5).r == 128)
        // 1 + (2−1)·0.5 = 1.5 → 2;  2 + (3−2)·0.5 = 2.5 → 2
        #expect(RGBA.mix(RGBA(r: 1, g: 2, b: 0), RGBA(r: 2, g: 3, b: 0), 0.5).r == 2)
        #expect(RGBA.mix(RGBA(r: 1, g: 2, b: 0), RGBA(r: 2, g: 3, b: 0), 0.5).g == 2)
    }

    @Test func brightenTruncatesBelowOneAndWhitensAbove() {
        #expect(RGBA.brighten(RGBA.classic, 0.55) == RGBA(r: 28, g: 123, b: 140))
        #expect(RGBA.brighten(RGBA.classic, 1) == RGBA.classic)
        #expect(RGBA.brighten(RGBA.classic, 1.3).r > 0x33)
    }

    @Test func semanticColorsWin() {
        let angry = FacePalette.color(of: FaceLibrary.parameters(for: .angry), theme: .matrix, time: 0, customHex: "#000000")
        #expect(angry == RGBA(argb: FaceLibrary.red))
        let idle = FacePalette.color(of: .init(), theme: .classic, time: 0, customHex: "#000000")
        #expect(idle == RGBA(r: 0x33, g: 0xE1, b: 0xFF))
    }

    @Test func hexAndHsv() {
        #expect(RGBA.parseHex("#FF2E88") == RGBA(r: 0xFF, g: 0x2E, b: 0x88))
        #expect(RGBA.parseHex("nope") == .classic)
        #expect(RGBA.hsv(0, 1, 1) == RGBA(r: 255, g: 0, b: 0))
        #expect(RGBA.hsv(120, 1, 1) == RGBA(r: 0, g: 255, b: 0))
        #expect(RGBA.hsv(-120, 1, 1) == RGBA(r: 0, g: 0, b: 255))
    }
}
