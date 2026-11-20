import AppKit

/// Island-ийг агуулах тунгалаг, focus авдаггүй panel.
/// - `.statusBar` level → menu bar-аас (level 24) дээгүүр.
/// - `.fullScreenAuxiliary` ЗОРИУДААР байхгүй: fullscreen app/game-ийн space-д харагдахгүй (game mode).
final class IslandPanel: NSPanel {
    /// Collapsed үед false (бусад app-аас focus булаахгүй), Expanded үед true (TextField бичих).
    var allowsKey = false

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
    }

    /// Island дээр left click (focus/activation-гүйгээр). M3-д control center нээхэд ашиглана.
    var onClick: (() -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { onClick?() }
        super.sendEvent(event)
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}
