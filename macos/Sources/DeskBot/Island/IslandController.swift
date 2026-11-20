import AppKit
import Observation
import SwiftUI
import DeskBotCore

/// Control center-ийн tab-ууд (M4-д бодит panel болно).
enum ControlTab: String, CaseIterable, Identifiable {
    case home = "Home", music = "Music", reminders = "Reminders", face = "Face", settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: "house"
        case .music: "music.note"
        case .reminders: "bell"
        case .face: "face.smiling"
        case .settings: "gearshape"
        }
    }
}

/// Island-ийн харагдах төлөв (SwiftUI view үүнийг уншина). Хэмжээ өөрчлөлтийг controller
/// `withAnimation(.island(grow:))`-аар тавьдаг тул view өөрөө animate хийнэ.
@MainActor
@Observable
final class IslandModel {
    var mode: IslandMode = .collapsed
    var islandSize = CGSize(width: 190, height: 34)
    var headerHeight: CGFloat = 34
    var faceWidth: CGFloat = 114
    /// Notch-ийг тойруулсан байрлал бол notch-ийн хэмжээ (нүд чихэнд). nil = энгийн pill.
    var notchSize: CGSize?
    var simulatedNotch = false
    var cornerRadius: CGFloat = 18
    /// Дэлгэцийн дээд ирмэгт наалдсан (дээд булан шулуун).
    var attachedTop = true
    var background: IslandBackground = .oled
    var backgroundOpacity = 0.96
    /// false бол face animation зогсоно (CPU хэмнэнэ).
    var faceVisible = false
    /// Auto-hide: дээш нуугдсан.
    var hiddenUp = false
    var pinned = false
    var selectedTab: ControlTab = .home
    var alertTitle = ""
    var alertTime = ""

    var facePaused: Bool { !faceVisible || hiddenUp }
}

/// Island-ийн UI-аас controller руу буцах үйлдлүүд.
@MainActor
struct IslandActions {
    var togglePin: () -> Void = {}
    var close: () -> Void = {}
    var finishAlert: (_ snoozed: Bool) -> Void = { _ in }
}

/// Island panel-ийн mode, байрлал, drag, auto-hide, click-through-ийг удирдана.
/// Цэвэр логик нь DeskBotCore-д (IslandModeMachine, AutoHideTracker, IslandSizing, IslandSnap).
@MainActor
final class IslandController {
    /// Panel-ийн island-аас илүү зай (BackEase overshoot тайрагдахгүй). C#: PadX 28, PadBottom 30.
    static let padX: CGFloat = 28
    static let padBottom: CGFloat = 30
    static let tickInterval: TimeInterval = 1.0 / 30 // C#: cursor timer 33ms

    private let settings: AppSettings
    let model = IslandModel()
    private let panel: IslandPanel
    private let face: FaceDriver
    private var machine = IslandModeMachine()
    private var autoHide = AutoHideTracker()
    private var geometry = ScreenGeometry(frame: .zero)
    private var observers: [NSObjectProtocol] = []
    private var keyMonitor: Any?
    private var tickTimer: Timer?
    private var animVersion = 0

    private(set) var isVisible = false
    /// Зорилтот (animation дууссаны дараах) island байрлал.
    private(set) var layout = IslandLayout(frame: .zero)
    var mode: IslandMode { machine.mode }

    /// Robot дээр click (Surprised + pulse).
    var onFaceClick: (() -> Void)?

    init(settings: AppSettings, face: FaceDriver) {
        self.settings = settings
        self.face = face
        panel = IslandPanel(contentRect: NSRect(x: 0, y: 0, width: 190, height: 34))

        var actions = IslandActions()
        actions.togglePin = { [weak self] in self?.settings.pinned.toggle() }
        actions.close = { [weak self] in self?.setMode(.collapsed) }
        actions.finishAlert = { [weak self] _ in self?.finishAlert() }
        let host = NSHostingView(rootView: IslandView(model: model, face: face, actions: actions))
        host.sizingOptions = [] // panel-ийн хэмжээг бид удирдана
        panel.contentView = host

        panel.isInPressRegion = { [weak self] p in self?.headerRect.contains(p) ?? false }
        panel.canDrag = { [weak self] in !(self?.settings.lockPosition ?? true) }
        panel.onClick = { [weak self] in self?.faceClicked() }
        panel.onDragEnded = { [weak self] in self?.dragEnded() }

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.relayout() }
        })
        // C# Deactivated: өөр app руу шилжвэл (pin-гүй үед) хаана.
        observers.append(nc.addObserver(forName: NSWindow.didResignKeyNotification,
                                        object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.outsideInteraction() }
        })
        // Esc — зөвхөн өөрийн panel-ийн key event (local monitor). Бусад app-ийн гарыг уншихгүй.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard e.keyCode == 53 else { return e }
            let handled = MainActor.assumeIsolated { self?.handleEscape() ?? false }
            return handled ? nil : e
        }
        observeSettings()
        model.pinned = settings.pinned
        apply(.collapsed, instant: true)
    }

    // MARK: - Public API

    /// Face-ийн төв (Cocoa screen координат, y дээшээ). Panel нь island-ийн дээд төвд тэгшилсэн
    /// тул чирэх болон animation-ий үед ч зөв.
    var faceCenterOnScreen: NSPoint {
        NSPoint(x: panel.frame.midX, y: panel.frame.maxY - model.headerHeight / 2)
    }

    var isHiddenUp: Bool { autoHide.isHidden }

    func show() {
        isVisible = true
        relayout()
        face.resetClock()
        model.faceVisible = true
        panel.orderFrontRegardless()
        startTicking()
    }

    func hide() {
        isVisible = false
        if machine.mode != .collapsed { apply(machine.set(.collapsed) ?? .collapsed, instant: true) }
        model.faceVisible = false
        tickTimer?.invalidate()
        tickTimer = nil
        panel.orderOut(nil)
    }

    func toggleVisible() { isVisible ? hide() : show() }

    func toggleControlCenter() {
        if !isVisible { show() }
        setMode(machine.mode == .expanded ? .collapsed : .expanded)
    }

    func resetPosition() {
        settings.offsetX = 0
        settings.topOffset = 0
        settings.dockScreen = ""
        relayout()
    }

    /// M4-ийн ReminderService холбогдох хүртэл debug цэснээс туршина.
    func showAlert(title: String, time: Date) {
        if !isVisible { show() }
        model.alertTitle = title
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        model.alertTime = "Reminder · " + f.string(from: time)
        setMode(.alert)
    }

    /// Global click (island-аас гадна). Glance хийж болох эсэхийг буцаана.
    func globalClick(at p: NSPoint) -> Bool {
        guard isVisible else { return false }
        if !layout.frame.contains(p) { outsideInteraction() }
        return !autoHide.isHidden
    }

    // MARK: - Mode

    private func setMode(_ m: IslandMode) {
        if let changed = machine.set(m) { apply(changed) }
    }

    private func handleEscape() -> Bool {
        guard let m = machine.escape() else { return false }
        apply(m)
        return true
    }

    private func faceClicked() {
        onFaceClick?()
        apply(machine.click())
    }

    private func finishAlert() {
        machine.finishAlert()
        apply(machine.mode)
    }

    private func outsideInteraction() {
        if let m = machine.outsideClick(pinned: settings.pinned) { apply(m) }
    }

    /// Mode-ийн хэмжээ, байрлал, key төлөвийг тавьж, island-ийг animate хийнэ (C# SetMode).
    private func apply(_ mode: IslandMode, instant: Bool = false) {
        guard let screen = ScreenProvider.screen(for: settings.dockScreen) else { return }
        geometry = ScreenProvider.geometry(of: screen)
        let sizing = IslandSizing(settings)
        let atNotch = settings.topOffset == 0 && settings.offsetX == 0
        let notch = atNotch ? geometry.notchRect?.size : nil
        let target = IslandLayout.place(screen: geometry, size: sizing.size(mode, notch: notch),
                                        topOffset: settings.topOffset, offsetX: settings.offsetX)
        let old = model.islandSize
        let new = target.frame.size
        layout = target

        // Key: Expanded үед л (Esc, TextField). Бусад үед focus-ийг буцааж өгнө.
        if mode == .expanded {
            panel.allowsKey = true
            if isVisible { panel.makeKeyAndOrderFront(nil) }
        } else if panel.allowsKey {
            panel.allowsKey = false
            if panel.isKeyWindow, isVisible {
                // Nonactivating panel-ээс key-ийг active app руу буцаах найдвартай арга.
                panel.orderOut(nil)
                panel.orderFrontRegardless()
            }
        }

        // Panel-ийг эхлээд хоёр хэмжээний томоор нь (animation тайрагдахгүй), дараа нь зорилтот хэмжээнд.
        placePanel(islandTopCenter: NSPoint(x: target.frame.midX, y: target.frame.maxY),
                   size: CGSize(width: max(old.width, new.width), height: max(old.height, new.height)))

        animVersion += 1
        let version = animVersion
        let grow = new.width * new.height >= old.width * old.height
        let fast = instant || settings.reducedMotion
        let update = { [self] in
            model.mode = mode
            model.islandSize = new
            model.headerHeight = sizing.headerHeight(mode, notch: notch)
            model.faceWidth = sizing.faceWidth(mode)
            model.notchSize = target.notchInIsland?.size
            model.simulatedNotch = ScreenProvider.simulateNotch && target.hasNotch
            model.cornerRadius = settings.cornerRadius + (mode == .expanded ? 8 : 0)
            model.attachedTop = settings.topOffset < 0.5
            model.background = settings.background
            model.backgroundOpacity = settings.backgroundOpacity
        }
        if fast {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t, update)
            placePanel(islandTopCenter: NSPoint(x: target.frame.midX, y: target.frame.maxY), size: new)
        } else {
            withAnimation(.island(grow: grow), update)
            let duration = grow ? IslandEasing.growSeconds : IslandEasing.shrinkSeconds
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.03) { [weak self] in
                guard let self, self.animVersion == version, !self.panel.isPressed else { return }
                self.placePanel(islandTopCenter: NSPoint(x: target.frame.midX, y: target.frame.maxY), size: new)
            }
        }
        if mode != .collapsed { setHiddenUp(false) }
    }

    private func placePanel(islandTopCenter c: NSPoint, size: CGSize) {
        let f = NSRect(x: (c.x - size.width / 2 - Self.padX).rounded(),
                       y: c.y - size.height - Self.padBottom,
                       width: (size.width + 2 * Self.padX).rounded(),
                       height: size.height + Self.padBottom)
        if panel.frame != f { panel.setFrame(f, display: true) }
    }

    private func relayout() { apply(machine.mode, instant: true) }

    /// Robot-ийн мөр (click/drag хийх хэсэг) — screen координат.
    private var headerRect: NSRect {
        guard !autoHide.isHidden else { return .zero }
        let r = layout.frame
        return NSRect(x: r.minX, y: r.maxY - model.headerHeight, width: r.width, height: model.headerHeight)
    }

    // MARK: - Drag

    private func dragEnded() {
        let top = NSPoint(x: panel.frame.midX, y: panel.frame.maxY)
        let probe = NSPoint(x: top.x, y: top.y - 4)
        let screen = NSScreen.screens.first { $0.frame.contains(probe) }
            ?? NSScreen.screens.min { distance($0.frame, probe) < distance($1.frame, probe) }
        guard let screen else { relayout(); return }
        let snap = IslandSnap.resolve(islandTopCenter: top, islandWidth: layout.frame.width,
                                      screen: ScreenProvider.geometry(of: screen))
        settings.dockScreen = ScreenProvider.id(of: screen)
        settings.offsetX = snap.offsetX
        settings.topOffset = snap.topOffset
        relayout() // утга өөрчлөгдөөгүй ч (snap буцаад 0,0) panel-ийг байранд нь тавина
        Log.info("Island moved: screen=\(settings.dockScreen) offsetX=\(snap.offsetX) top=\(snap.topOffset)")
    }

    private func distance(_ r: NSRect, _ p: NSPoint) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX), dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return dx * dx + dy * dy
    }

    // MARK: - Tick (hover, click-through, auto-hide)

    private func startTicking() {
        guard tickTimer == nil else { return }
        let t = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common) // menu нээлттэй үед ч ажиллана
        tickTimer = t
    }

    private func tick() {
        guard isVisible, !panel.isPressed else { return } // чирэх үед event-ийг panel өөрөө авна
        let now = Date()
        let p = NSEvent.mouseLocation
        let r = layout.frame

        if autoHide.update(now: now, enabled: settings.autoHide, mode: machine.mode, cursor: p, island: r) {
            setHiddenUp(autoHide.isHidden)
        }

        // Click-through: island-ийн (нуугдаагүй) хэсэг дээр л mouse event авна. Pad болон
        // нуугдсан island menu bar / доорх app-д саад болохгүй.
        let inside = !autoHide.isHidden && r.insetBy(dx: -2, dy: -2).contains(p)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }

        machine.pointer(inside: inside, now: now,
                        hoverDelay: Double(settings.hoverDelayMs) / 1000,
                        autoCollapse: Double(settings.autoCollapseMs) / 1000)
        let textFocused = panel.firstResponder is NSText
        if let m = machine.tick(now: now, pinned: settings.pinned, textFocused: textFocused) { apply(m) }
    }

    private func setHiddenUp(_ hidden: Bool) {
        guard model.hiddenUp != hidden else { return }
        if settings.reducedMotion {
            model.hiddenUp = hidden
        } else {
            withAnimation(.easeOut(duration: 0.26)) { model.hiddenUp = hidden } // C#: CubicEase 260ms
        }
        if !hidden { face.resetClock() }
    }

    // MARK: - Settings

    private func observeSettings() {
        withObservationTracking {
            _ = (settings.islandWidth, settings.islandHeight, settings.hoverWidth, settings.panelWidth,
                 settings.panelHeight, settings.topOffset, settings.offsetX, settings.dockScreen,
                 settings.cornerRadius, settings.background, settings.backgroundOpacity,
                 settings.pinned, settings.autoHide)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.model.pinned = self.settings.pinned
                if !self.settings.autoHide { self.autoHide = AutoHideTracker(); self.setHiddenUp(false) }
                if !self.panel.isPressed { self.relayout() }
                self.observeSettings()
            }
        }
    }
}

// MARK: - Animation

/// WPF-ийн яг easing: grow → BackEase(0.22) 360ms, shrink → CubicEase 240ms.
struct IslandCurveAnimation: CustomAnimation {
    var duration: TimeInterval
    var back: Bool

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        guard time < duration else { return nil }
        let t = time / duration
        return value.scaled(by: back ? IslandEasing.backOut(t) : IslandEasing.cubicOut(t))
    }
}

extension Animation {
    static func island(grow: Bool) -> Animation {
        Animation(IslandCurveAnimation(duration: grow ? IslandEasing.growSeconds : IslandEasing.shrinkSeconds,
                                       back: grow))
    }
}
