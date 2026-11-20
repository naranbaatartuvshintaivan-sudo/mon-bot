import CoreGraphics
import Foundation

// C# порт: src/DeskBot.App/UI/Controls/RobotFace.cs — OnRender() доторх хэмжээ/байрлалын тооцоо ба BuildEye().
// Координат: face-ийн local, origin дээд зүүн, y доошоо.

public struct EyeShapeMetrics: Equatable, Sendable {
    public var aspect: Double
    public var roundness: Double

    public static func of(_ shape: EyeShape) -> EyeShapeMetrics {
        switch shape {
        case .pill: EyeShapeMetrics(aspect: 0.58, roundness: 0.5)
        case .circle: EyeShapeMetrics(aspect: 1.0, roundness: 0.5)
        case .square: EyeShapeMetrics(aspect: 0.92, roundness: 0.16)
        case .rounded: EyeShapeMetrics(aspect: 0.8, roundness: 0.36)
        }
    }
}

/// Нэг нүдний төв ба хэмжээ (blink-ээс өмнөх).
public struct EyePlacement: Equatable, Sendable {
    public var side: Int          // -1 зүүн, +1 баруун
    public var center: CGPoint
    public var width: Double
    public var height: Double
}

public struct FaceLayout: Equatable, Sendable {
    public var size: CGSize
    public var baseW: Double
    public var baseH: Double
    public var spacing: Double
    public var center: CGPoint    // look/bounce/offset орсон хоёр нүдний дундаж төв
    public var left: EyePlacement
    public var right: EyePlacement

    /// - Parameter spacingOverride: notch-тэй island дээр нүдийг notch-ийн хоёр талын "чих"-нд
    ///   байрлуулахын тулд хоёр нүдний төв хоорондын зайг шууд өгнө (EyeSpacing тохиргоог үл тооно).
    public init(size: CGSize, params p: FaceParameters, shape: EyeShape, eyeSize: Double, eyeSpacing: Double,
                look: SIMD2<Double>, time: Double, notice: Double, clickPulse: Double,
                reducedMotion: Bool, performanceMode: Bool, spacingOverride: Double? = nil) {
        let W = Double(size.width), H = Double(size.height)
        let m = EyeShapeMetrics.of(shape)
        let baseH = min(H * 0.62 * eyeSize, H * 0.92)
        let baseW = baseH * m.aspect
        let spacing = spacingOverride ?? max(baseW * 1.95 * eyeSpacing, baseW * 1.2)
        let breathe = reducedMotion || performanceMode ? 1 : 1 + 0.022 * sin(time * 1.7)
        let bounce = reducedMotion ? 0 : -p.bounce * H * abs(sin(time * p.bounceSpeed * 0.5))
        let pop = 1 + 0.08 * notice + 0.22 * clickPulse
        let cx = W / 2 + look.x * baseW * 0.6
        let cy = H / 2 + p.offsetY * H + bounce + look.y * baseH * 0.28

        func eye(_ side: Int) -> EyePlacement {
            let sc = (side > 0 ? p.rightEyeScale : 1) * breathe * pop
            return EyePlacement(side: side,
                                center: CGPoint(x: cx + Double(side) * spacing / 2,
                                                y: cy + (side > 0 ? p.rightEyeLift * H : 0)),
                                width: baseW * p.eyeWidth * sc,
                                height: baseH * p.eyeHeight * sc)
        }

        self.size = size
        self.baseW = baseW
        self.baseH = baseH
        self.spacing = spacing
        self.center = CGPoint(x: cx, y: cy)
        self.left = eye(-1)
        self.right = eye(1)
    }

    public var eyes: [EyePlacement] { [left, right] }

    /// Overlay-ийн баруун/зүүн хэвтээ байрлал (C# DrawOverlays).
    public var overlayRight: Double {
        min(Double(size.width) / 2 + spacing / 2 + baseW * 1.05, Double(size.width) - baseH * 0.35)
    }
    public var overlayLeft: Double {
        max(Double(size.width) / 2 - spacing / 2 - baseW * 1.05, baseH * 0.35)
    }
}

public enum FaceGeometry {
    /// Нүд = rounded rect − эргэдэг дээд lid − доод эллипс (C# CombinedGeometry Exclude).
    /// - Parameters:
    ///   - h: blink орсон өндөр.
    ///   - cornerRadius: `min(w, h) × roundness`.
    ///   - lidAngle: градус. + = дотор тал доош (уурласан). Баруун нүдэнд толин тусгал.
    public static func eyePath(center c: CGPoint, width w: Double, height h: Double, cornerRadius: Double,
                               lidTop: Double, lidAngle: Double, bottomCut: Double, side: Int) -> CGPath {
        let rect = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
        let r = max(0, min(cornerRadius, min(w, h) / 2))
        var g: CGPath = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)

        if lidTop > 0.001 {
            // Lid-ийн доод ирмэг (cx, top + lidTop·h)-ээр дамжина.
            let pivotY = rect.minY + lidTop * h
            let lidRect = CGRect(x: c.x - w * 1.5, y: pivotY - h * 2, width: w * 3, height: h * 2)
            // WPF RotateTransform(angle, cx, cy): y-доошоо координатад эерэг = цагийн зүүний дагуу. CG-д ч мөн адил.
            let angle = lidAngle * Double(-side) * .pi / 180
            var t = CGAffineTransform(translationX: c.x, y: pivotY)
                .rotated(by: angle)
                .translatedBy(x: -c.x, y: -pivotY)
            g = g.subtracting(CGPath(rect: lidRect, transform: &t))
        }

        if bottomCut > 0.001 {
            // Доороос эллипсээр тайрч ∩ хэлбэр (баярласан нүд)
            let rx = w * 0.78
            let ry = h * 0.95
            let ecy = rect.maxY + ry - bottomCut * h * 1.25
            let ellipse = CGPath(ellipseIn: CGRect(x: c.x - rx, y: ecy - ry, width: rx * 2, height: ry * 2), transform: nil)
            g = g.subtracting(ellipse)
        }
        return g
    }
}
