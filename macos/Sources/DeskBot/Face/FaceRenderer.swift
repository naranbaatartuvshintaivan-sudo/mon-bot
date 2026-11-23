import AppKit
import SwiftUI
import DeskBotCore

// C# порт: src/DeskBot.App/UI/Controls/RobotFace.cs — OnRender, BuildFill, UpdateGlow, Draw* функцууд.
// Тоонууд C#-тай ижил. Координат WPF-тэй адил (origin дээд зүүн, y доошоо) — flipped NSView / CGContext.
// SwiftUI Canvas биш Core Graphics: TimelineView+Canvas-ийн frame бүрийн overhead (~13% CPU @60fps) хэт өндөр байсан.

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
    var cgColor: CGColor {
        CGColor(srgbRed: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, alpha: Double(a) / 255)
    }
}

enum FaceRenderer {
    /// WPF DropShadowEffect.BlurRadius → CGContext shadow blur. Нүдээр M2-ийн SwiftUI хувилбартай тааруулсан.
    static let glowBlurScale = 1.0

    /// Fill: цул өнгө эсвэл (Aurora) bounding box-ийн диагоналаар gradient.
    private enum Fill {
        case color(RGBA)
        case gradient(RGBA, RGBA)
    }

    /// Glow (C# DropShadowEffect) параметр. nil = унтарсан (performance mode эсвэл intensity≈0).
    struct Glow: Equatable {
        var color: RGBA
        var blur: Double
    }

    static func glow(snapshot s: FaceSnapshot, style: FaceStyle) -> Glow? {
        guard !style.performanceMode && style.glowIntensity > 0.01 else { return nil }
        let p = s.params
        let col = FacePalette.current(from: s.from, to: s.to, t: s.easedT, brightness: p.brightness,
                                      theme: style.theme, time: s.time, customHex: style.customColor)
        let blur = 4 + 16 * style.glowIntensity * p.glow * (1 + 0.3 * s.notice)
        let opacity = min(max(0.4 + 0.55 * style.glowIntensity, 0), 1)
        return Glow(color: col.withAlpha(UInt8(255 * opacity)), blur: blur * glowBlurScale)
    }

    /// - drawGlow: false бол glow-ийг дуудагч өөрөө (CALayer.shadow, GPU) зурна.
    ///   CG-ийн shadow нь CPU Gaussian blur → 60fps-д хамгийн үнэтэй хэсэг байсан.
    static func draw(_ cg: CGContext, size: CGSize, snapshot s: FaceSnapshot, style: FaceStyle, drawGlow: Bool = true) {
        let W = Double(size.width), H = Double(size.height)
        guard W >= 4, H >= 4 else { return }

        let p = s.params
        let col = FacePalette.current(from: s.from, to: s.to, t: s.easedT, brightness: p.brightness,
                                      theme: style.theme, time: s.time, customHex: style.customColor)
        let layout = FaceLayout(size: size, params: p, shape: style.eyeShape, eyeSize: style.eyeSize,
                                eyeSpacing: style.eyeSpacing, look: s.look, time: s.time, notice: s.notice,
                                clickPulse: s.clickPulse, reducedMotion: style.reducedMotion,
                                performanceMode: style.performanceMode, spacingOverride: style.spacingOverride)

        cg.saveGState()
        defer { cg.restoreGState() }
        // Glow — C# UpdateGlow. Transparency layer → shadow нь бүх нүд+overlay-ийн нийлбэр дээр нэг удаа.
        let g = drawGlow ? glow(snapshot: s, style: style) : nil
        if let g { cg.setShadow(offset: .zero, blur: g.blur, color: g.color.cgColor) }
        if g != nil { cg.beginTransparencyLayer(auxiliaryInfo: nil) }
        drawEyes(cg, layout: layout, snapshot: s, style: style, color: col)
        drawOverlays(cg, layout: layout, params: p, color: col, time: s.time)
        if g != nil { cg.endTransparencyLayer() }
    }

    /// Debug / export: offscreen bitmap.
    static func image(size: CGSize, scale: CGFloat, snapshot: FaceSnapshot, style: FaceStyle, drawGlow: Bool = true) -> CGImage? {
        let w = Int(size.width * scale), h = Int(size.height * scale)
        guard w > 0, h > 0, let cg = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                               space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        cg.translateBy(x: 0, y: CGFloat(h))
        cg.scaleBy(x: scale, y: -scale) // y доошоо
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        draw(cg, size: size, snapshot: snapshot, style: style, drawGlow: drawGlow)
        NSGraphicsContext.restoreGraphicsState()
        return cg.makeImage()
    }

    // MARK: - Primitives

    private static func fill(_ cg: CGContext, _ path: CGPath, _ fill: Fill) {
        switch fill {
        case .color(let c):
            cg.addPath(path)
            cg.setFillColor(c.cgColor)
            cg.fillPath()
        case .gradient(let a, let b):
            // WPF LinearGradientBrush (0,0)→(1,1): shape-ийн bounding box-д харьцангуй
            let r = path.boundingBoxOfPath
            guard let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                     colors: [a.cgColor, b.cgColor] as CFArray, locations: [0, 1]) else { return }
            cg.saveGState()
            cg.addPath(path)
            cg.clip()
            cg.drawLinearGradient(g, start: CGPoint(x: r.minX, y: r.minY), end: CGPoint(x: r.maxX, y: r.maxY),
                                  options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            cg.restoreGState()
        }
    }

    private static func fill(_ cg: CGContext, _ path: CGPath, _ c: RGBA) { fill(cg, path, .color(c)) }

    private static func stroke(_ cg: CGContext, _ path: CGPath, _ c: RGBA, _ width: Double, cap: CGLineCap = .butt) {
        cg.addPath(path)
        cg.setStrokeColor(c.cgColor)
        cg.setLineWidth(width)
        cg.setLineCap(cap)
        cg.strokePath()
    }

    private static func ellipse(_ x: Double, _ y: Double, _ r: Double) -> CGPath {
        CGPath(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2), transform: nil)
    }

    private static func roundedRect(_ r: CGRect, _ radius: Double) -> CGPath {
        let rad = max(0, min(radius, Double(min(r.width, r.height)) / 2))
        return CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
    }

    // MARK: - Eyes

    private static func eyeFill(color col: RGBA, snapshot s: FaceSnapshot, style: FaceStyle) -> Fill {
        let p = s.params
        if style.theme == .aurora && s.from.semanticColor == nil && s.to.semanticColor == nil {
            let a = RGBA.brighten(FacePalette.themeColor(.aurora, time: s.time, customHex: style.customColor), p.brightness)
            let b = RGBA.brighten(FacePalette.themeColor(.aurora, secondary: true, time: s.time, customHex: style.customColor), p.brightness)
            return .gradient(a, b)
        }
        if style.theme == .matrix && p.semanticColor == nil { return .color(col.withAlpha(0xB0)) }
        return .color(col)
    }

    private static func drawEyes(_ cg: CGContext, layout: FaceLayout, snapshot s: FaceSnapshot,
                                 style: FaceStyle, color col: RGBA) {
        let p = s.params
        let round = EyeShapeMetrics.of(style.eyeShape).roundness
        let eyeFill = eyeFill(color: col, snapshot: s, style: style)

        for eye in layout.eyes {
            let (ex, ey) = (Double(eye.center.x), Double(eye.center.y))
            let w = eye.width, h = eye.height
            let side = eye.side

            if p.overlay.contains(.ring) { drawRingEye(cg, ex, ey, max(w, h), col, side, s.time); continue }
            if p.overlay.contains(.wave) { drawWaveEye(cg, ex, ey, w, h, eyeFill, side, s.time); continue }
            if p.overlay.contains(.pixelX) { drawPixelX(cg, ex, ey, min(w, h) * 1.1, col, s.time); continue }

            let hb = h * max(0.07, s.blink)
            let path = FaceGeometry.eyePath(center: eye.center, width: w, height: hb, cornerRadius: min(w, hb) * round,
                                            lidTop: p.lidTop, lidAngle: p.lidAngle, bottomCut: p.bottomCut, side: side)

            if s.glitching {
                let jitter = (Double.random(in: 0..<1) - 0.5) * 4
                for (dx, c) in [(-2.5 + jitter, RGBA(a: 0x90, r: 0xFF, g: 0x30, b: 0x60)),
                                (2.5 + jitter, RGBA(a: 0x90, r: 0x30, g: 0xF0, b: 0xFF))] {
                    var t = CGAffineTransform(translationX: dx, y: 0)
                    if let moved = path.copy(using: &t) { fill(cg, moved, c) }
                }
            }

            fill(cg, path, eyeFill)

            if style.theme == .matrix && !style.performanceMode && p.semanticColor == nil {
                drawMatrixRain(cg, clip: path, ex, ey, w, hb, side, s.time)
            }
        }
    }

    private static func drawRingEye(_ cg: CGContext, _ x: Double, _ y: Double, _ d: Double,
                                    _ col: RGBA, _ side: Int, _ time: Double) {
        let r = d * 0.4
        stroke(cg, ellipse(x, y, r), col.withAlpha(0x40), d * 0.12)
        let a0 = time * 5.5 * Double(side)
        let arc = CGMutablePath()
        // y-доошоо координатад өсөх өнцөг = цагийн зүүний дагуу (WPF SweepDirection.Clockwise).
        arc.addArc(center: CGPoint(x: x, y: y), radius: r, startAngle: a0, endAngle: a0 + .pi * 0.62, clockwise: false)
        stroke(cg, arc, col, d * 0.16, cap: .round)
    }

    private static func drawWaveEye(_ cg: CGContext, _ x: Double, _ y: Double, _ w: Double, _ h: Double,
                                    _ f: Fill, _ side: Int, _ time: Double) {
        let bars = 4
        let bw = w / 6
        let gap = (w - Double(bars) * bw) / Double(bars - 1)
        for k in 0..<bars {
            let amp = 0.25 + 0.75 * abs(sin(time * 7 + Double(k) * 0.9 + Double(side)))
            let bh = h * amp
            let bx = x - w / 2 + Double(k) * (bw + gap)
            fill(cg, roundedRect(CGRect(x: bx, y: y - bh / 2, width: bw, height: bh), bw / 2), f)
        }
    }

    private static func drawPixelX(_ cg: CGContext, _ x: Double, _ y: Double, _ size: Double,
                                   _ col: RGBA, _ time: Double) {
        if Int(time * 9) % 11 == 0 { return } // "эвдэрсэн" анивчилт
        let n = 5
        let px = size / Double(n)
        let path = CGMutablePath()
        for i in 0..<n {
            for j in 0..<n where i == j || i + j == n - 1 {
                path.addRect(CGRect(x: x - size / 2 + Double(i) * px + 0.5, y: y - size / 2 + Double(j) * px + 0.5,
                                    width: max(0, px - 1), height: max(0, px - 1)))
            }
        }
        fill(cg, path, col)
    }

    private static func drawMatrixRain(_ cg: CGContext, clip: CGPath, _ ex: Double, _ ey: Double,
                                       _ w: Double, _ h: Double, _ side: Int, _ time: Double) {
        cg.saveGState()
        defer { cg.restoreGState() }
        cg.addPath(clip)
        cg.clip()
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
                fill(cg, CGPath(rect: CGRect(x: x, y: top + head - Double(tr) * sq * 1.25, width: sq, height: sq), transform: nil),
                     RGBA(a: a, r: 0xC8, g: 0xFF, b: 0xD8))
            }
        }
    }

    // MARK: - Overlays

    private static func drawOverlays(_ cg: CGContext, layout: FaceLayout, params p: FaceParameters,
                                     color col: RGBA, time: Double) {
        let o = p.overlay
        guard !o.isEmpty else { return }
        let W = Double(layout.size.width), H = Double(layout.size.height)
        let baseW = layout.baseW, baseH = layout.baseH
        let right = layout.overlayRight, left = layout.overlayLeft

        if o.contains(.sparkles) {
            let spots = [(left, H * 0.22), (right, H * 0.3), (W / 2, H * 0.1)]
            for (i, spot) in spots.enumerated() {
                let s = baseH * 0.2 * (0.55 + 0.45 * abs(sin(time * 5 + Double(i) * 1.7)))
                drawStar(cg, spot.0, spot.1, s, RGBA.mix(col, .white, 0.6))
            }
        }
        if o.contains(.bubble) {
            let bw = baseW * 1.15, bh = baseH * 0.55
            let bx = right - bw / 2, by = H * 0.08
            fill(cg, roundedRect(CGRect(x: bx, y: by, width: bw, height: bh), bh / 2.2), col)
            for i in 0..<3 {
                let a = UInt8(120 + 135 * max(0, sin(time * 6 - Double(i) * 0.8)))
                fill(cg, ellipse(bx + bw * (0.28 + Double(i) * 0.22), by + bh / 2, bh * 0.12),
                     RGBA(a: a, r: 0x05, g: 0x06, b: 0x08))
            }
        }
        if o.contains(.clock) {
            let r = baseH * 0.28
            let c = CGPoint(x: right, y: H * 0.3)
            let lw = max(1.2, r * 0.18)
            stroke(cg, ellipse(c.x, c.y, r), col, lw)
            let a = time * 3
            let hands = CGMutablePath()
            hands.move(to: c)
            hands.addLine(to: CGPoint(x: c.x + sin(a) * r * 0.75, y: c.y - cos(a) * r * 0.75))
            hands.move(to: c)
            hands.addLine(to: CGPoint(x: c.x + r * 0.45, y: c.y))
            stroke(cg, hands, col, lw)
        }
        if o.contains(.battery) {
            let bw = baseW * 0.95, bh = baseH * 0.42
            let bx = right - bw / 2, by = H * 0.18
            stroke(cg, roundedRect(CGRect(x: bx, y: by, width: bw, height: bh), 1.5), col, 1.2)
            fill(cg, CGPath(rect: CGRect(x: bx + bw, y: by + bh * 0.3, width: bw * 0.1, height: bh * 0.4), transform: nil), col)
            if Int(time * 2) % 2 == 0 {
                fill(cg, CGPath(rect: CGRect(x: bx + 2, y: by + 2, width: max(0, (bw - 4) * 0.2), height: max(0, bh - 4)), transform: nil),
                     RGBA(argb: FaceLibrary.red))
            }
        }
        if o.contains(.notes) {
            for i in 0..<2 {
                let f = (time * 0.6 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                drawGlyph(cg, i == 0 ? "♪" : "♫", left - Double(i) * baseW * 0.3, H * 0.75 - f * H * 0.6,
                          baseH * 0.48, col.withAlpha(UInt8(255 * (1 - f))))
            }
        }
        if o.contains(.question) {
            drawGlyph(cg, "?", right, H * 0.32 + sin(time * 3) * H * 0.04, baseH * 0.62, col)
        }
        if o.contains(.zzz) {
            for i in 0..<3 {
                let f = (time * 0.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                drawGlyph(cg, "z", right + f * baseW * 0.5, H * 0.6 - f * H * 0.5, baseH * (0.25 + f * 0.3),
                          col.withAlpha(UInt8(230 * (1 - f))))
            }
        }
        if o.contains(.warning) {
            let s = baseH * 0.5
            let c = CGPoint(x: right, y: H * 0.32)
            let tri = CGMutablePath()
            tri.move(to: CGPoint(x: c.x, y: c.y - s * 0.55))
            tri.addLine(to: CGPoint(x: c.x + s * 0.55, y: c.y + s * 0.45))
            tri.addLine(to: CGPoint(x: c.x - s * 0.55, y: c.y + s * 0.45))
            tri.closeSubpath()
            fill(cg, tri, RGBA(argb: FaceLibrary.amber))
            drawGlyph(cg, "!", c.x, c.y + s * 0.05, s * 0.7, RGBA(r: 0x05, g: 0x06, b: 0x08))
        }
        if o.contains(.check) {
            // Ногоон дугуй badge + ✓. Эхний ~0.25с-д pop хийж томорно (time нь animator-ын үргэлжилсэн цаг).
            let r = baseH * 0.3 * (1 + 0.06 * sin(time * 6))
            let c = CGPoint(x: right, y: H * 0.3)
            fill(cg, ellipse(c.x, c.y, r), RGBA(argb: FaceLibrary.green))
            let tick = CGMutablePath()
            tick.move(to: CGPoint(x: c.x - r * 0.45, y: c.y + r * 0.02))
            tick.addLine(to: CGPoint(x: c.x - r * 0.1, y: c.y + r * 0.38))
            tick.addLine(to: CGPoint(x: c.x + r * 0.5, y: c.y - r * 0.35))
            cg.saveGState()
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            stroke(cg, tick, RGBA(r: 0x05, g: 0x06, b: 0x08), max(1.4, r * 0.28))
            cg.restoreGState()
        }
    }

    private static func drawStar(_ cg: CGContext, _ x: Double, _ y: Double, _ s: Double, _ c: RGBA) {
        let i = s * 0.25
        let g = CGMutablePath()
        g.move(to: CGPoint(x: x, y: y - s))
        for pt in [(x + i, y - i), (x + s, y), (x + i, y + i), (x, y + s), (x - i, y + i), (x - s, y), (x - i, y - i)] {
            g.addLine(to: CGPoint(x: pt.0, y: pt.1))
        }
        g.closeSubpath()
        fill(cg, g, c)
    }

    /// C#: Segoe UI Bold FormattedText, төвд нь. Glyph-ийн CGPath-ийг cache-ээс авч scale хийнэ —
    /// NSAttributedString-ийн typesetting frame бүр хийх нь (zzz, ♪) хамгийн үнэтэй хэсэг байсан.
    private static func drawGlyph(_ cg: CGContext, _ text: String, _ x: Double, _ y: Double, _ size: Double, _ c: RGBA) {
        guard size >= 1, let g = GlyphCache.glyph(text) else { return }
        let k = size / GlyphCache.unitSize
        // Font координат y дээшээ → flipped context-д y-ийг эргүүлнэ. Төв = typographic box-ийн төв.
        var t = CGAffineTransform(translationX: x, y: y).scaledBy(x: k, y: -k)
            .translatedBy(x: -g.advance / 2, y: -g.boxMidY)
        guard let path = g.path.copy(using: &t) else { return }
        fill(cg, path, c)
    }
}

/// Overlay-ийн тэмдэгтүүдийн (z ♪ ♫ ? !) path — system bold, шаардлагатай бол fallback font.
/// Thread-safe (lock) — render нь main thread дээр, export ч бас дуудаж болно.
enum GlyphCache {
    static let unitSize: Double = 100

    struct Glyph: @unchecked Sendable { // CGPath immutable
        let path: CGPath
        let advance: Double
        /// NSAttributedString-ийн мөрийн хайрцгийн (descent…ascent) төв — өмнөх байрлалтай ижил.
        let boxMidY: Double
    }

    nonisolated(unsafe) private static var cache: [String: Glyph] = [:]
    private static let lock = NSLock()

    static func glyph(_ text: String) -> Glyph? {
        lock.lock()
        defer { lock.unlock() }
        if let g = cache[text] { return g }
        let base = NSFont.systemFont(ofSize: unitSize, weight: .bold) as CTFont
        let font = CTFontCreateForString(base, text as CFString, CFRange(location: 0, length: (text as NSString).length))
        let chars = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        guard CTFontGetGlyphsForCharacters(font, chars, &glyphs, chars.count), let glyph = glyphs.first,
              let path = CTFontCreatePathForGlyph(font, glyph, nil) else { return nil }
        var adv = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, [glyph], &adv, 1)
        let g = Glyph(path: path, advance: adv.width,
                      boxMidY: (CTFontGetAscent(font) - CTFontGetDescent(font)) / 2)
        cache[text] = g
        return g
    }
}
