import AppKit
import QuartzCore
import SwiftUI
import DeskBotCore

/// Render хурд — өөрчлөгдөхөд л RobotFaceView-ийн body дахин үнэлэгдэж TimelineView-ийн schedule солигдоно.
@MainActor
@Observable
final class FaceRate {
    var demand: FaceFrameDemand = .active
}

/// FaceAnimator-ийг эзэмшиж, TimelineView-ийн frame бүрд урагшлуулна.
/// `@Observable` БИШ — frame бүр state өөрчлөгддөг тул SwiftUI invalidation-ийг TimelineView л удирдана.
/// Нүд тайван үед 10Hz (idle) / 20Hz (ambient) руу буурна (`FaceAnimator.frameDemand`).
@MainActor
final class FaceDriver {
    let rate = FaceRate()
    private var rateUpdatePending = false
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
                             glitchTheme: s.theme == .glitch, continuousTheme: s.theme == .matrix)
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
        animator.step(rawDt: dt, maxDt: rate.demand == .active ? FaceAnimator.maxFrameDt : FaceAnimator.maxIdleFrameDt)
        // Render дундуур observable өөрчлөхгүй — дараагийн runloop-д.
        let want = animator.frameDemand
        if want != rate.demand && !rateUpdatePending {
            rateUpdatePending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.rateUpdatePending = false
                self.rate.demand = self.animator.frameDemand
            }
        }
    }

    /// Оролт (cursor, click, expression) ирэхэд шууд бүтэн fps руу сэрээнэ (10Hz-ийн хоцрогдолгүй).
    private func wakeIfNeeded() {
        animator.settings = Self.animatorSettings(settings)
        if animator.frameDemand > rate.demand { rate.demand = animator.frameDemand }
    }

    /// Нуугдсан үед дараагийн frame-ийн dt-г 0-оос эхлүүлнэ.
    func resetClock() { lastDate = nil }

    func setExpression(_ e: RobotExpression) { animator.setExpression(e); wakeIfNeeded() }
    func pulse() { animator.pulse(); wakeIfNeeded() }

    /// Cocoa screen координат (y дээшээ) → face төвөөс (y доошоо) offset.
    func setCursor(screen p: NSPoint, faceCenter c: NSPoint) {
        animator.setCursor(dx: Double(p.x - c.x), dy: Double(c.y - p.y))
        wakeIfNeeded()
    }

    func glance(screen p: NSPoint, faceCenter c: NSPoint) {
        animator.glance(dx: Double(p.x - c.x), dy: Double(c.y - p.y))
        wakeIfNeeded()
    }
}

/// Robot нүүр — static зураг ашиглахгүй, frame бүр geometry-ээр зурна (Core Graphics, layer-backed NSView).
/// Frame хурд (`FaceRate.demand`):
/// - active → `NSView.displayLink` (дэлгэцийн refresh; performance mode-д 30fps)
/// - ambient 20Hz / idle 10Hz → display link зогсоож энгийн Timer
/// - paused (нуугдсан, auto-hide) → бүх зүйл зогсоно.
@MainActor
final class RobotFaceNSView: NSView {
    let driver: FaceDriver
    var notchWidth: Double? { didSet { if notchWidth != oldValue { needsDisplay = true } } }
    var paused = true { didSet { if paused != oldValue { reschedule() } } }

    private var link: CADisplayLink?
    private var timer: Timer?
    private var scheduled: (demand: FaceFrameDemand, perf: Bool)?
    private var rateObservation = false

    init(driver: FaceDriver) {
        self.driver = driver
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.masksToBounds = false
        layer?.drawsAsynchronously = false
        setAccessibilityLabel("DeskBot robot face")
        setAccessibilityRole(.image)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil } // click нь island (panel) руу

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeRate()
        reschedule()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    /// Debug: зурсан frame-ийн тоо (CPU хэмжилтэд).
    private(set) static var framesDrawn = 0
    private var appliedGlow: FaceRenderer.Glow??

    override func draw(_ dirtyRect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        Self.framesDrawn += 1
        let size = bounds.size
        let spacing = notchWidth.map { Double(size.width) / 2 + $0 / 2 }
        let snapshot = driver.snapshot
        let style = driver.style(spacingOverride: spacing)
        FaceRenderer.draw(cg, size: size, snapshot: snapshot, style: style, drawGlow: false)
        applyGlow(FaceRenderer.glow(snapshot: snapshot, style: style))
    }

    /// Glow = CALayer shadow (render server-т GPU-ээр, CPU blur-гүй). Өөрчлөгдсөн үед л тавина.
    private func applyGlow(_ g: FaceRenderer.Glow?) {
        guard let layer, appliedGlow != .some(g) else { return }
        appliedGlow = .some(g)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let g {
            layer.shadowColor = g.color.withAlpha(255).cgColor
            layer.shadowOpacity = Float(g.color.a) / 255
            // CALayer shadowRadius ≈ Gaussian σ·2 → CG blur-ийн тал орчим (нүдээр тааруулна).
            layer.shadowRadius = g.blur / 2
            layer.shadowOffset = .zero
        } else {
            layer.shadowOpacity = 0
        }
        CATransaction.commit()
    }

    private var lastDrawnKey: FaceVisualKey?

    /// Нэг frame: animator урагшлуулаад дахин зурна. Idle үед харагдах өөрчлөлт (≥0.2pt / өнгө)
    /// байхгүй бол зурахгүй — CA commit нь frame бүрийн хамгийн үнэтэй хэсэг.
    @objc private func frame(_ sender: Any?) {
        driver.advance(to: Date())
        if scheduled?.demand == .idle, !inLiveResize {
            let key = FaceVisualKey(driver: driver, size: bounds.size, notchWidth: notchWidth)
            if key == lastDrawnKey { return }
            lastDrawnKey = key
        } else {
            lastDrawnKey = nil
        }
        needsDisplay = true
    }

    private func observeRate() {
        guard !rateObservation else { return }
        rateObservation = true
        withObservationTracking {
            _ = driver.rate.demand
            _ = driver.settings.performanceMode
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.rateObservation = false
                self.reschedule()
                self.observeRate()
            }
        }
    }

    private func reschedule() {
        let running = !paused && window != nil
        let want = running ? (driver.rate.demand, driver.settings.performanceMode) : nil
        if let w = want, let cur = scheduled, cur.demand == w.0, cur.perf == w.1 { return }
        if want == nil && scheduled == nil && link == nil && timer == nil { return }

        link?.invalidate(); link = nil
        timer?.invalidate(); timer = nil
        scheduled = want.map { ($0.0, $0.1) }
        guard let (demand, perf) = want else {
            driver.resetClock() // дахин эхлэхэд том dt үсрэлт гаргахгүй
            return
        }
        if let interval = demand.interval(performanceMode: perf), demand < .gentle {
            let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.frame(nil) }
            }
            t.tolerance = interval * 0.2 // CPU wake-up-ийг нэгтгэх боломж
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else {
            let l = displayLink(target: self, selector: #selector(frame(_:)))
            // gentle (idle wander) эсвэл performance mode → 30fps, vsync-тэй (Timer-ээс гөлгөр).
            if perf || demand == .gentle { l.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 30, preferred: 30) }
            l.add(to: .main, forMode: .common)
            link = l
        }
        frame(nil)
    }

    func stop() {
        paused = true
    }
}

/// Idle frame-д зурах эсэхийг шийдэх "харагдах төлөв": нүдний байрлал/хэмжээ 0.2pt-ээр бүхэлчилсэн + өнгө.
struct FaceVisualKey: Equatable {
    var eyes: [Int]
    var color: RGBA

    @MainActor
    init(driver: FaceDriver, size: CGSize, notchWidth: Double?) {
        let s = driver.snapshot
        let spacing = notchWidth.map { Double(size.width) / 2 + $0 / 2 }
        let style = driver.style(spacingOverride: spacing)
        let layout = FaceLayout(size: size, params: s.params, shape: style.eyeShape, eyeSize: style.eyeSize,
                                eyeSpacing: style.eyeSpacing, look: s.look, time: s.time, notice: s.notice,
                                clickPulse: s.clickPulse, reducedMotion: style.reducedMotion,
                                performanceMode: style.performanceMode, spacingOverride: style.spacingOverride)
        let q = { (v: Double) in Int((v * 5).rounded()) } // 0.2pt
        eyes = layout.eyes.flatMap { [q(Double($0.center.x)), q(Double($0.center.y)), q($0.width), q($0.height * s.blink)] }
        color = FacePalette.current(from: s.from, to: s.to, t: s.easedT, brightness: s.params.brightness,
                                    theme: style.theme, time: s.time, customHex: style.customColor)
    }
}

/// SwiftUI wrapper (island-ийн layout/animation SwiftUI-д үлдэнэ).
struct RobotFaceView: NSViewRepresentable {
    let driver: FaceDriver
    /// Notch-ийг тойруулсан island: нүд нь notch-ийн хоёр талын чихний төвд. View-ийн бодит
    /// (animate хийгдэж буй) өргөнөөс тооцно: spacing = W/2 + notchW/2.
    var notchWidth: Double?
    var paused = false

    func makeNSView(context: Context) -> RobotFaceNSView {
        let v = RobotFaceNSView(driver: driver)
        v.notchWidth = notchWidth
        v.paused = paused
        return v
    }

    func updateNSView(_ v: RobotFaceNSView, context: Context) {
        v.notchWidth = notchWidth
        v.paused = paused
    }

    static func dismantleNSView(_ v: RobotFaceNSView, coordinator: ()) { v.stop() }
}
