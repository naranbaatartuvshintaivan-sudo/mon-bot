import AppKit
import SwiftUI
import DeskBotCore

/// FaceAnimator-ийг эзэмшиж, TimelineView-ийн frame бүрд урагшлуулна.
/// `@Observable` БИШ — frame бүр state өөрчлөгддөг тул SwiftUI invalidation-ийг TimelineView л удирдана.
@MainActor
final class FaceDriver {
    let settings: AppSettings
    private(set) var animator: FaceAnimator
    private var lastDate: Date?

    init(settings: AppSettings, random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.settings = settings
        animator = FaceAnimator(settings: Self.animatorSettings(settings), random: random)
    }

    static func animatorSettings(_ s: AppSettings) -> FaceAnimatorSettings {
        FaceAnimatorSettings(followCursor: s.followCursor, reducedMotion: s.reducedMotion,
                             blinkFrequency: s.blinkFrequency, animationSpeed: s.animationSpeed,
                             glitchTheme: s.theme == .glitch)
    }

    var expression: RobotExpression { animator.expression }
    var isCursorNear: Bool { animator.isCursorNear }
    var snapshot: FaceSnapshot { FaceSnapshot(animator) }

    func style(spacingOverride: Double?) -> FaceStyle {
        FaceStyle(theme: settings.theme, eyeShape: settings.eyeShape, eyeSize: settings.eyeSize,
                  eyeSpacing: settings.eyeSpacing, glowIntensity: settings.glowIntensity,
                  customColor: settings.customColor, reducedMotion: settings.reducedMotion,
                  performanceMode: settings.performanceMode, spacingOverride: spacingOverride)
    }

    /// TimelineView-ийн огноогоор урагшилна. Эхний frame (эсвэл pause-ийн дараа) dt тооцохгүй — C#-тай ижил.
    func advance(to date: Date) {
        defer { lastDate = date }
        guard let last = lastDate else { return }
        let dt = date.timeIntervalSince(last)
        guard dt > 0 else { return } // нэг frame-д давхар дуудагдсан
        animator.settings = Self.animatorSettings(settings)
        animator.step(rawDt: dt)
    }

    /// Нуугдсан үед дараагийн frame-ийн dt-г 0-оос эхлүүлнэ.
    func resetClock() { lastDate = nil }

    func setExpression(_ e: RobotExpression) { animator.setExpression(e) }
    func pulse() { animator.pulse() }

    /// Cocoa screen координат (y дээшээ) → face төвөөс (y доошоо) offset.
    func setCursor(screen p: NSPoint, faceCenter c: NSPoint) {
        animator.setCursor(dx: Double(p.x - c.x), dy: Double(c.y - p.y))
    }

    func glance(screen p: NSPoint, faceCenter c: NSPoint) {
        animator.glance(dx: Double(p.x - c.x), dy: Double(c.y - p.y))
    }
}

/// Robot нүүр — static зураг ашиглахгүй, frame бүр geometry-ээр зурна.
/// Performance mode: 30fps (C#: 2 frame тутамд нэг render).
struct RobotFaceView: View {
    let driver: FaceDriver
    var spacingOverride: Double?
    var paused = false

    var body: some View {
        let perf = driver.settings.performanceMode
        TimelineView(.animation(minimumInterval: perf ? 1.0 / 30 : nil, paused: paused)) { timeline in
            Canvas(opaque: false, rendersAsynchronously: false) { ctx, size in
                driver.advance(to: timeline.date)
                FaceRenderer.draw(&ctx, size: size, snapshot: driver.snapshot,
                                  style: driver.style(spacingOverride: spacingOverride))
            }
        }
        .allowsHitTesting(false)
        .accessibilityLabel("DeskBot robot face")
    }
}
