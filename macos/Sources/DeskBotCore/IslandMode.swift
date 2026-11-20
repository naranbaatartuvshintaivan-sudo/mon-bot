import CoreGraphics
import Foundation

// C# порт: src/DeskBot.App/UI/Windows/IslandWindow.xaml.cs — Mode, SizeFor, SetMode, OnIslandEnter/Leave,
// OnCollapseTimer, OnFaceClick, UpdateAutoHide, OnDragEnd. AppKit-аас салгасан цэвэр логик → test хийж болно.

public enum IslandMode: String, CaseIterable, Sendable {
    case collapsed = "Collapsed"
    case hover = "Hover"
    case alert = "Alert"
    case expanded = "Expanded"
}

// MARK: - Sizing

/// Mode бүрийн island хэмжээ (C# SizeFor) + notch-тэй дэлгэцийн тохируулга.
public struct IslandSizing: Equatable, Sendable {
    /// Alert bar-ийн өндөр (C#: +58).
    public static let alertBarHeight: CGFloat = 58
    /// Notch-тэй үед hover-ийн цаг/огнооны мөр notch-ийн доор (header-т багтахгүй).
    public static let notchInfoRowHeight: CGFloat = 20

    public var islandWidth: CGFloat = 190
    public var islandHeight: CGFloat = 34
    public var hoverWidth: CGFloat = 360
    public var panelWidth: CGFloat = 640
    public var panelHeight: CGFloat = 420

    public init(islandWidth: CGFloat = 190, islandHeight: CGFloat = 34, hoverWidth: CGFloat = 360,
                panelWidth: CGFloat = 640, panelHeight: CGFloat = 420) {
        self.islandWidth = islandWidth
        self.islandHeight = islandHeight
        self.hoverWidth = hoverWidth
        self.panelWidth = panelWidth
        self.panelHeight = panelHeight
    }

    public init(_ s: AppSettings) {
        self.init(islandWidth: s.islandWidth, islandHeight: s.islandHeight, hoverWidth: s.hoverWidth,
                  panelWidth: s.panelWidth, panelHeight: s.panelHeight)
    }

    /// Face-ийн мөрийн өндөр. Notch-тэй бол notch-оос намхан байж болохгүй.
    public func headerHeight(_ mode: IslandMode, notch: CGSize? = nil) -> CGFloat {
        let base = mode == .collapsed ? islandHeight : islandHeight + 8
        return max(base, notch?.height ?? 0)
    }

    /// C#: Collapsed → clamp(W·0.6, 80, 160), бусад → 124.
    public func faceWidth(_ mode: IslandMode) -> CGFloat {
        mode == .collapsed ? min(max(islandWidth * 0.6, 80), 160) : 124
    }

    public func size(_ mode: IslandMode, notch: CGSize? = nil) -> CGSize {
        let header = headerHeight(mode, notch: notch)
        var s: CGSize
        switch mode {
        case .collapsed: s = CGSize(width: islandWidth, height: header)
        case .hover:     s = CGSize(width: hoverWidth, height: header + (notch != nil ? Self.notchInfoRowHeight : 0))
        case .alert:     s = CGSize(width: max(hoverWidth, 400), height: header + Self.alertBarHeight)
        case .expanded:  s = CGSize(width: panelWidth, height: panelHeight)
        }
        if let n = notch { s.width = max(s.width, n.width + 2 * IslandLayout.minEarWidth) }
        return s
    }
}

// MARK: - Mode machine

/// Hover delay, auto-collapse timer, click/Esc/гадна click, pin, alert. Цаг гаднаас (`now`) өгөгдөнө.
public struct IslandModeMachine: Sendable {
    public private(set) var mode: IslandMode = .collapsed
    public private(set) var isPointerInside = false
    public private(set) var hoverAt: Date?
    public private(set) var collapseAt: Date?

    public init() {}

    /// Cursor island-ийн дотор/гадна (C# MouseEnter/MouseLeave). `hoverDelay`, `autoCollapse` — секунд.
    public mutating func pointer(inside: Bool, now: Date, hoverDelay: TimeInterval, autoCollapse: TimeInterval) {
        guard inside != isPointerInside else { return }
        isPointerInside = inside
        if inside {
            collapseAt = nil
            if mode == .collapsed { hoverAt = now.addingTimeInterval(max(0.001, hoverDelay)) }
        } else {
            hoverAt = nil
            if mode == .hover || mode == .expanded {
                let t = mode == .expanded ? max(autoCollapse, 0.9) : autoCollapse
                collapseAt = now.addingTimeInterval(max(0.001, t))
            }
        }
    }

    /// Timer-ууд. Mode өөрчлөгдвөл шинэ mode-ийг буцаана.
    @discardableResult
    public mutating func tick(now: Date, pinned: Bool, textFocused: Bool = false) -> IslandMode? {
        if let h = hoverAt, now >= h {
            hoverAt = nil
            if mode == .collapsed && isPointerInside { return set(.hover) }
        }
        if let c = collapseAt, now >= c {
            collapseAt = nil
            if isPointerInside { return nil }              // resize-ийн үеийн хуурамч leave
            if mode == .alert { return nil }               // Done/Snooze хүртэл
            if mode == .expanded && (pinned || textFocused) { return nil }
            if mode == .hover || mode == .expanded { return set(.collapsed) }
        }
        return nil
    }

    /// Robot (header) дээр click — C# OnFaceClick.
    @discardableResult
    public mutating func click() -> IslandMode {
        switch mode {
        case .expanded: set(.collapsed)
        case .alert, .collapsed, .hover: set(.expanded) // Alert → M4-д Reminders tab нээнэ
        }
        return mode
    }

    /// Esc — pin-ээс үл хамааран хаана (C#-тай ижил).
    @discardableResult
    public mutating func escape() -> IslandMode? {
        mode == .expanded ? set(.collapsed) : nil
    }

    /// Island-аас гадна click эсвэл panel focus алдсан (C# Deactivated).
    @discardableResult
    public mutating func outsideClick(pinned: Bool) -> IslandMode? {
        mode == .expanded && !pinned ? set(.collapsed) : nil
    }

    public mutating func showAlert() { set(.alert) }

    /// Alert дууссаны дараа cursor дээр нь байвал Hover, эс бөгөөс Collapsed.
    public mutating func finishAlert() {
        guard mode == .alert else { return }
        set(isPointerInside ? .hover : .collapsed)
    }

    @discardableResult
    public mutating func set(_ m: IslandMode) -> IslandMode? {
        guard m != mode else { return nil }
        mode = m
        hoverAt = nil
        collapseAt = nil
        return m
    }
}

// MARK: - Auto-hide

/// Collapsed үед 2.5с cursor ойртохгүй бол дээш нуугдана; дээд ирмэгт ирэхэд гарна (C# UpdateAutoHide).
public struct AutoHideTracker: Sendable {
    public static let delay: TimeInterval = 2.5
    /// Нуугдсан үед харагдах хэсэг (pt).
    public static let peek: CGFloat = 4
    /// Island-ийн хажуу тийш "ойр" гэж тооцох зай, дээд ирмэгийн зай.
    public static let sideMargin: CGFloat = 40
    public static let edgeMargin: CGFloat = 8

    public private(set) var isHidden = false
    private var lastNear: Date?

    public init() {}

    /// - island: island-ийн frame (Cocoa, y дээшээ), нуугдаагүй байрлал.
    /// - Returns: isHidden өөрчлөгдсөн бол true.
    @discardableResult
    public mutating func update(now: Date, enabled: Bool, mode: IslandMode, cursor p: CGPoint, island: CGRect) -> Bool {
        let was = isHidden
        defer { if lastNear == nil { lastNear = now } }
        guard enabled, mode == .collapsed else {
            isHidden = false
            lastNear = now
            return was != isHidden
        }
        if Self.isNear(cursor: p, island: island, hidden: isHidden) {
            lastNear = now
            isHidden = false
        } else if !isHidden, now.timeIntervalSince(lastNear ?? now) > Self.delay {
            isHidden = true
        }
        return was != isHidden
    }

    public static func isNear(cursor p: CGPoint, island r: CGRect, hidden: Bool) -> Bool {
        let visible = hidden ? CGRect(x: r.minX, y: r.maxY - peek, width: r.width, height: peek) : r
        if visible.insetBy(dx: -2, dy: -2).contains(p) { return true }
        return abs(p.x - r.midX) < r.width / 2 + sideMargin && p.y >= r.maxY - edgeMargin
    }
}

// MARK: - Drag snap

/// Чирж дууссаны дараа island-ийн байрлалыг offset болгож, magnetic snap хийнэ (C# OnDragEnd).
public enum IslandSnap {
    public static let centerThreshold: CGFloat = 18
    public static let topThreshold: CGFloat = 14

    /// - islandTopCenter: island-ийн дээд төв цэг (Cocoa screen координат).
    /// - screen: island аль дэлгэц дээр байгаа.
    /// - Returns: (offsetX, topOffset) — settings-д хадгалах утга (бүхэл pt).
    public static func resolve(islandTopCenter p: CGPoint, islandWidth: CGFloat,
                               screen: ScreenGeometry) -> (offsetX: CGFloat, topOffset: CGFloat) {
        let f = screen.frame
        var offX = p.x - f.midX
        var top = f.maxY - p.y
        if abs(offX) < centerThreshold { offX = 0 }
        if top < topThreshold { top = 0 }
        // Notch-той дэлгэцийн дээд ирмэгт notch-той давхцвал notch-ийг тойруулсан байрлал руу наалдана
        // (эс бөгөөс pill-ийн нэг хэсэг notch-ийн ард далдлагдана).
        if top == 0, let n = screen.notchRect {
            let half = islandWidth / 2
            let center = f.midX + offX
            if center + half > n.minX && center - half < n.maxX { offX = 0 }
        }
        return (offX.rounded(), max(0, top).rounded())
    }
}

// MARK: - Easing

/// WPF easing-ийн яг томьёо (t ∈ [0,1]).
public enum IslandEasing {
    public static let growSeconds = 0.36
    public static let shrinkSeconds = 0.24
    public static let backAmplitude = 0.22

    /// WPF BackEase EaseOut: 1 − f(1−t), f(t) = t³ − t·A·sin(πt).
    public static func backOut(_ t: Double, amplitude a: Double = backAmplitude) -> Double {
        let u = 1 - min(max(t, 0), 1)
        return 1 - (u * u * u - u * a * sin(.pi * u))
    }

    /// WPF CubicEase EaseOut.
    public static func cubicOut(_ t: Double) -> Double {
        let u = 1 - min(max(t, 0), 1)
        return 1 - u * u * u
    }
}
