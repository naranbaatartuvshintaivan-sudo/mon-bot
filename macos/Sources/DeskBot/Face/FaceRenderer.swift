import SwiftUI
import DeskBotCore

// C# порт: src/DeskBot.App/UI/Controls/RobotFace.cs — OnRender, BuildFill, UpdateGlow, Draw* функцууд.
// Тоонууд C#-тай ижил. Canvas координат WPF-тэй адил (origin дээд зүүн, y доошоо).

/// Нэг frame зурахад хэрэгтэй animation төлөв (FaceAnimator-аас авсан хуулбар).
struct FaceSnapshot {
    var from: FaceParameters
    var to: FaceParameters
    var easedT: Double
    var params: FaceParameters
    var look: SIMD2<Double>
    var blink: Double
    var notice: Double
    var clickPulse: Double
    var time: Double
    var glitching: Bool

    init(_ a: FaceAnimator) {
        from = a.from
        to = a.to
        easedT = a.easedT
        params = a.currentParameters
        look = a.look
        blink = a.blinkOpenness
        notice = a.notice
        clickPulse = a.clickPulse
        time = a.time
        glitching = a.isGlitching
    }
}

/// Зурахад хэрэгтэй тохиргоо (AppSettings-ийн хэсэг + island-ийн байрлал).
struct FaceStyle {
    var theme: FaceTheme = .classic
    var eyeShape: EyeShape = .rounded
    var eyeSize = 1.0
    var eyeSpacing = 1.0
    var glowIntensity = 0.7
    var customColor = AppSettings.defaultColor
    var reducedMotion = false
    var performanceMode = false
    /// Notch-тэй island: нүдний төв хоорондын зай (point).
    var spacingOverride: Double?
}

extension RGBA {
    var color: Color {
        Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

enum FaceRenderer {
    /// WPF DropShadowEffect.BlurRadius → SwiftUI shadow radius. WPF-ийн BlurRadius нь blur kernel-ийн
    /// бүтэн радиус, SwiftUI-ийнх Gaussian-д ойр тул нүдээр харьцуулж ~0.5 гэж авсан (яг тэнцүү биш).
    static let glowRadiusScale = 0.5

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, snapshot s: FaceSnapshot, style: FaceStyle) {
        let W = Double(size.width), H = Double(size.height)
        guard W >= 4, H >= 4 else { return }

        let p = s.params
        let col = FacePalette.current(from: s.from, to: s.to, t: s.easedT, brightness: p.brightness,
                                      theme: style.theme, time: s.time, customHex: style.customColor)
        let layout = FaceLayout(size: size, params: p, shape: style.eyeShape, eyeSize: style.eyeSize,
                                eyeSpacing: style.eyeSpacing, look: s.look, time: s.time, notice: s.notice,
                                clickPulse: s.clickPulse, reducedMotion: style.reducedMotion,
                                performanceMode: style.performanceMode, spacingOverride: style.spacingOverride)

        // Glow — C# UpdateGlow: performance mode эсвэл intensity≈0 үед унтарна.
        var outer = ctx
        if !style.performanceMode && style.glowIntensity > 0.01 {
            let blur = 4 + 16 * style.glowIntensity * p.glow * (1 + 0.3 * s.notice)
            let opacity = min(max(0.4 + 0.55 * style.glowIntensity, 0), 1)
            outer.addFilter(.shadow(color: col.color.opacity(opacity), radius: blur * glowRadiusScale))
        }
        // Layer → shadow бүх нүд+overlay-ийн нийлбэр дээр нэг удаа (WPF Effect шиг).
        outer.drawLayer { layer in
            drawEyes(&layer, layout: layout, snapshot: s, style: style, color: col)
            drawOverlays(&layer, layout: layout, params: p, color: col, time: s.time)
        }
    }

    // MARK: - Eyes

    private static func fill(for rect: CGRect, color col: RGBA, snapshot s: FaceSnapshot, style: FaceStyle) -> GraphicsContext.Shading {
        let p = s.params
        if style.theme == .aurora && s.from.semanticColor == nil && s.to.semanticColor == nil {
            let a = RGBA.brighten(FacePalette.themeColor(.aurora, time: s.time, customHex: style.customColor), p.brightness)
            let b = RGBA.brighten(FacePalette.themeColor(.aurora, secondary: true, time: s.time, customHex: style.customColor), p.brightness)
            // WPF LinearGradientBrush (0,0)→(1,1): shape-ийн bounding box-д харьцангуй
            return .linearGradient(Gradient(colors: [a.color, b.color]),
                                   startPoint: CGPoint(x: rect.minX, y: rect.minY),
                                   endPoint: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        if style.theme == .matrix && p.semanticColor == nil {
            return .color(col.withAlpha(0xB0).color)
        }
        return .color(col.color)
    }

    private static func drawEyes(_ ctx: inout GraphicsContext, layout: FaceLayout, snapshot s: FaceSnapshot,
                                 style: FaceStyle, color col: RGBA) {
        let p = s.params
        let round = EyeShapeMetrics.of(style.eyeShape).roundness

        for eye in layout.eyes {
            let (ex, ey) = (Double(eye.center.x), Double(eye.center.y))
            let w = eye.width, h = eye.height
            let side = eye.side

            if p.overlay.contains(.ring) { drawRingEye(&ctx, ex, ey, max(w, h), col, side, s.time); continue }
            if p.overlay.contains(.wave) {
                let rect = CGRect(x: ex - w / 2, y: ey - h / 2, width: w, height: h)
                drawWaveEye(&ctx, ex, ey, w, h, fill(for: rect, color: col, snapshot: s, style: style), side, s.time)
                continue
            }
            if p.overlay.contains(.pixelX) { drawPixelX(&ctx, ex, ey, min(w, h) * 1.1, col, s.time); continue }

            let hb = h * max(0.07, s.blink)
            let cg = FaceGeometry.eyePath(center: eye.center, width: w, height: hb, cornerRadius: min(w, hb) * round,
                                          lidTop: p.lidTop, lidAngle: p.lidAngle, bottomCut: p.bottomCut, side: side)
            let path = Path(cg)

            if s.glitching {
                let jitter = (Double.random(in: 0..<1) - 0.5) * 4
                ctx.fill(path.offsetBy(dx: -2.5 + jitter, dy: 0), with: .color(RGBA(a: 0x90, r: 0xFF, g: 0x30, b: 0x60).color))
                ctx.fill(path.offsetBy(dx: 2.5 + jitter, dy: 0), with: .color(RGBA(a: 0x90, r: 0x30, g: 0xF0, b: 0xFF).color))
            }

            ctx.fill(path, with: fill(for: path.boundingRect, color: col, snapshot: s, style: style))

            if style.theme == .matrix && !style.performanceMode && p.semanticColor == nil {
                drawMatrixRain(&ctx, clip: path, ex, ey, w, hb, side, s.time)
            }
        }
    }

    private static func drawRingEye(_ ctx: inout GraphicsContext, _ x: Double, _ y: Double, _ d: Double,
                                    _ col: RGBA, _ side: Int, _ time: Double) {
        let r = d * 0.4
        let c = CGPoint(x: x, y: y)
        ctx.stroke(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                   with: .color(col.withAlpha(0x40).color), lineWidth: d * 0.12)

        let a0 = time * 5.5 * Double(side)
        let a1 = a0 + Double.pi * 0.62
        var arc = Path()
        // y-доошоо координатад өсөх өнцөг = цагийн зүүний дагуу (WPF SweepDirection.Clockwise).
        // SwiftUI-ийн `clockwise` нь y-дээшээ утгаар тул false.
        arc.addArc(center: c, radius: r, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
        ctx.stroke(arc, with: .color(col.color), style: StrokeStyle(lineWidth: d * 0.16, lineCap: .round))
    }

    private static func drawWaveEye(_ ctx: inout GraphicsContext, _ x: Double, _ y: Double, _ w: Double, _ h: Double,
                                    _ fill: GraphicsContext.Shading, _ side: Int, _ time: Double) {
        let bars = 4
        let bw = w / 6
        let gap = (w - Double(bars) * bw) / Double(bars - 1)
        for k in 0..<bars {
            let amp = 0.25 + 0.75 * abs(sin(time * 7 + Double(k) * 0.9 + Double(side)))
            let bh = h * amp
            let bx = x - w / 2 + Double(k) * (bw + gap)
            ctx.fill(Path(roundedRect: CGRect(x: bx, y: y - bh / 2, width: bw, height: bh), cornerRadius: bw / 2), with: fill)
        }
    }

    private static func drawPixelX(_ ctx: inout GraphicsContext, _ x: Double, _ y: Double, _ size: Double,
                                   _ col: RGBA, _ time: Double) {
        if Int(time * 9) % 11 == 0 { return } // "эвдэрсэн" анивчилт
        let n = 5
        let px = size / Double(n)
        var path = Path()
        for i in 0..<n {
            for j in 0..<n where i == j || i + j == n - 1 {
                path.addRect(CGRect(x: x - size / 2 + Double(i) * px + 0.5, y: y - size / 2 + Double(j) * px + 0.5,
                                    width: max(0, px - 1), height: max(0, px - 1)))
            }
        }
        ctx.fill(path, with: .color(col.color))
    }

    private static func drawMatrixRain(_ ctx: inout GraphicsContext, clip: Path, _ ex: Double, _ ey: Double,
                                       _ w: Double, _ h: Double, _ side: Int, _ time: Double) {
        var c = ctx
        c.clip(to: clip)
        let cols = 4
        let cw = w / Double(cols)
        let sq = cw * 0.62
        for k in 0..<cols {
            let speed = h * (1.4 + Double(k % 3) * 0.45)
            let span = h + sq * 4
            let head = (time * speed + (Double(k) * 13.7 + Double(side) * 5)).truncatingRemainder(dividingBy: span) - sq * 2
            let x = ex - w / 2 + Double(k) * cw + (cw - sq) / 2
            let top = ey - h / 2
            for tr in 0..<3 {
                let a: UInt8 = tr == 0 ? 255 : tr == 1 ? 140 : 60
                c.fill(Path(CGRect(x: x, y: top + head - Double(tr) * sq * 1.25, width: sq, height: sq)),
                       with: .color(RGBA(a: a, r: 0xC8, g: 0xFF, b: 0xD8).color))
            }
        }
    }

    // MARK: - Overlays

    private static func drawOverlays(_ ctx: inout GraphicsContext, layout: FaceLayout, params p: FaceParameters,
                                     color col: RGBA, time: Double) {
        let o = p.overlay
        guard !o.isEmpty else { return }
        let W = Double(layout.size.width), H = Double(layout.size.height)
        let baseW = layout.baseW, baseH = layout.baseH
        let right = layout.overlayRight, left = layout.overlayLeft
        let brush = GraphicsContext.Shading.color(col.color)

        if o.contains(.sparkles) {
            let spots = [(left, H * 0.22), (right, H * 0.3), (W / 2, H * 0.1)]
            for (i, spot) in spots.enumerated() {
                let s = baseH * 0.2 * (0.55 + 0.45 * abs(sin(time * 5 + Double(i) * 1.7)))
                drawStar(&ctx, spot.0, spot.1, s, .color(RGBA.mix(col, .white, 0.6).color))
            }
        }
        if o.contains(.bubble) {
            let bw = baseW * 1.15, bh = baseH * 0.55
            let bx = right - bw / 2, by = H * 0.08
            ctx.fill(Path(roundedRect: CGRect(x: bx, y: by, width: bw, height: bh), cornerRadius: bh / 2.2), with: brush)
            for i in 0..<3 {
                let a = UInt8(120 + 135 * max(0, sin(time * 6 - Double(i) * 0.8)))
                let cx = bx + bw * (0.28 + Double(i) * 0.22), cy = by + bh / 2, r = bh * 0.12
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                         with: .color(RGBA(a: a, r: 0x05, g: 0x06, b: 0x08).color))
            }
        }
        if o.contains(.clock) {
            let r = baseH * 0.28
            let c = CGPoint(x: right, y: H * 0.3)
            let lw = max(1.2, r * 0.18)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: brush, lineWidth: lw)
            let a = time * 3
            var hands = Path()
            hands.move(to: c)
            hands.addLine(to: CGPoint(x: c.x + sin(a) * r * 0.75, y: c.y - cos(a) * r * 0.75))
            hands.move(to: c)
            hands.addLine(to: CGPoint(x: c.x + r * 0.45, y: c.y))
            ctx.stroke(hands, with: brush, lineWidth: lw)
        }
        if o.contains(.battery) {
            let bw = baseW * 0.95, bh = baseH * 0.42
            let bx = right - bw / 2, by = H * 0.18
            ctx.stroke(Path(roundedRect: CGRect(x: bx, y: by, width: bw, height: bh), cornerRadius: 1.5), with: brush, lineWidth: 1.2)
            ctx.fill(Path(CGRect(x: bx + bw, y: by + bh * 0.3, width: bw * 0.1, height: bh * 0.4)), with: brush)
            if Int(time * 2) % 2 == 0 {
                ctx.fill(Path(CGRect(x: bx + 2, y: by + 2, width: max(0, (bw - 4) * 0.2), height: max(0, bh - 4))),
                         with: .color(RGBA(argb: FaceLibrary.red).color))
            }
        }
        if o.contains(.notes) {
            for i in 0..<2 {
                let f = (time * 0.6 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                let a = UInt8(255 * (1 - f))
                drawGlyph(&ctx, i == 0 ? "♪" : "♫", left - Double(i) * baseW * 0.3, H * 0.75 - f * H * 0.6,
                          baseH * 0.48, col.withAlpha(a))
            }
        }
        if o.contains(.question) {
            drawGlyph(&ctx, "?", right, H * 0.32 + sin(time * 3) * H * 0.04, baseH * 0.62, col)
        }
        if o.contains(.zzz) {
            for i in 0..<3 {
                let f = (time * 0.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                drawGlyph(&ctx, "z", right + f * baseW * 0.5, H * 0.6 - f * H * 0.5, baseH * (0.25 + f * 0.3),
                          col.withAlpha(UInt8(230 * (1 - f))))
            }
        }
        if o.contains(.warning) {
            let s = baseH * 0.5
            let c = CGPoint(x: right, y: H * 0.32)
            var tri = Path()
            tri.move(to: CGPoint(x: c.x, y: c.y - s * 0.55))
            tri.addLine(to: CGPoint(x: c.x + s * 0.55, y: c.y + s * 0.45))
            tri.addLine(to: CGPoint(x: c.x - s * 0.55, y: c.y + s * 0.45))
            tri.closeSubpath()
            ctx.fill(tri, with: .color(RGBA(argb: FaceLibrary.amber).color))
            drawGlyph(&ctx, "!", c.x, c.y + s * 0.05, s * 0.7, RGBA(r: 0x05, g: 0x06, b: 0x08))
        }
    }

    private static func drawStar(_ ctx: inout GraphicsContext, _ x: Double, _ y: Double, _ s: Double,
                                 _ shading: GraphicsContext.Shading) {
        let i = s * 0.25
        var g = Path()
        g.move(to: CGPoint(x: x, y: y - s))
        for pt in [(x + i, y - i), (x + s, y), (x + i, y + i), (x, y + s), (x - i, y + i), (x - s, y), (x - i, y - i)] {
            g.addLine(to: CGPoint(x: pt.0, y: pt.1))
        }
        g.closeSubpath()
        ctx.fill(g, with: shading)
    }

    /// C#: Segoe UI Bold FormattedText, хайрцгийн төвд. macOS: SF (system) bold.
    private static func drawGlyph(_ ctx: inout GraphicsContext, _ text: String, _ x: Double, _ y: Double,
                                  _ size: Double, _ c: RGBA) {
        guard size >= 1 else { return }
        ctx.draw(Text(text).font(.system(size: size, weight: .bold)).foregroundStyle(c.color),
                 at: CGPoint(x: x, y: y), anchor: .center)
    }
}
