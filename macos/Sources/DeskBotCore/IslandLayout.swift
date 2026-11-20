import CoreGraphics

/// Нэг дэлгэцийн island байрлалд хэрэгтэй геометр (Cocoa координат: origin доод зүүн, y дээшээ).
/// AppKit-аас хамааралгүй тул test хийж болно — `NSScreen`-ээс app талд бөглөнө.
public struct ScreenGeometry: Equatable, Sendable {
    public var frame: CGRect
    /// `NSScreen.safeAreaInsets.top` — 0 бол notch байхгүй.
    public var safeAreaTop: CGFloat
    /// `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea` (notch-ийн хоёр талын menu bar хэсэг).
    public var auxiliaryTopLeft: CGRect?
    public var auxiliaryTopRight: CGRect?

    public init(frame: CGRect, safeAreaTop: CGFloat = 0, auxiliaryTopLeft: CGRect? = nil, auxiliaryTopRight: CGRect? = nil) {
        self.frame = frame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeft = auxiliaryTopLeft
        self.auxiliaryTopRight = auxiliaryTopRight
    }

    /// Notch-ийн тэгш өнцөгт (screen координатаар). Notch-гүй бол nil.
    public var notchRect: CGRect? {
        guard safeAreaTop > 0, let l = auxiliaryTopLeft, let r = auxiliaryTopRight else { return nil }
        let width = r.minX - l.maxX
        guard width > 0 else { return nil }
        return CGRect(x: l.maxX, y: frame.maxY - safeAreaTop, width: width, height: safeAreaTop)
    }
}

public struct IslandLayout: Equatable, Sendable {
    /// Panel-ийн frame (screen координат). Panel = island, илүү зай байхгүй → click-through асуудалгүй.
    public var frame: CGRect
    /// Island дотор notch-ийн эзлэх хэсэг (island-ийн local координат, origin доод зүүн). nil = хуурамч notch (pill).
    public var notchInIsland: CGRect?

    public init(frame: CGRect, notchInIsland: CGRect? = nil) {
        self.frame = frame
        self.notchInIsland = notchInIsland
    }

    public var hasNotch: Bool { notchInIsland != nil }

    /// Notch-ийн хоёр талд нүд багтах хамгийн бага "чих"-ний өргөн.
    public static let minEarWidth: CGFloat = 44

    /// Collapsed island-ийн байрлал (M1 API — `place`-ийн товчлол).
    public static func collapsed(screen: ScreenGeometry, width: CGFloat, height: CGFloat,
                                 topOffset: CGFloat = 0, offsetX: CGFloat = 0) -> IslandLayout {
        place(screen: screen, size: CGSize(width: width, height: height), topOffset: topOffset, offsetX: offsetX)
    }

    /// Ямар ч mode-ийн island-ийн байрлал.
    /// - Notch-тэй, offset-гүй: notch-ийг бүрэн тойруулж, хоёр талд нь чих гаргана (нүд нь чихэнд).
    /// - Notch-гүй (эсвэл хэрэглэгч зөөсөн): дэлгэцийн дээд ирмэгт, menu bar-ийн дээгүүр хар pill.
    public static func place(screen: ScreenGeometry, size: CGSize,
                             topOffset: CGFloat = 0, offsetX: CGFloat = 0) -> IslandLayout {
        let f = screen.frame
        let width = min(size.width, f.width)
        if topOffset == 0, offsetX == 0, let notch = screen.notchRect {
            let w = min(max(width, notch.width + 2 * minEarWidth), f.width)
            let h = max(size.height, notch.height)
            var x = (notch.midX - w / 2).rounded()
            x = min(max(x, f.minX), f.maxX - w)
            let frame = CGRect(x: x, y: f.maxY - h, width: w.rounded(), height: h)
            let local = CGRect(x: notch.minX - frame.minX, y: h - notch.height, width: notch.width, height: notch.height)
            return IslandLayout(frame: frame, notchInIsland: local)
        }

        var x = f.midX - width / 2 + offsetX
        x = min(max(x, f.minX), f.maxX - width) // дэлгэцээс гарахгүй
        let y = f.maxY - topOffset - size.height
        return IslandLayout(frame: CGRect(x: x.rounded(), y: max(y, f.minY), width: width, height: size.height),
                            notchInIsland: nil)
    }

    /// Notch-ийн хоёр чихний төв хоорондын зай (face-ийн spacingOverride). Notch-гүй бол nil.
    public var earSpacing: Double? {
        guard let n = notchInIsland else { return nil }
        return Double((n.maxX + frame.width) / 2 - n.minX / 2)
    }
}
