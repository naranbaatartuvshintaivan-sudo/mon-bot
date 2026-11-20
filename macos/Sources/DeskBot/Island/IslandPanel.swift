import AppKit

/// Island-ийг агуулах тунгалаг, focus авдаггүй panel.
/// - `.statusBar` level → menu bar-аас (level 24) дээгүүр.
/// - `.fullScreenAuxiliary` ЗОРИУДААР байхгүй: fullscreen app/game-ийн space-д харагдахгүй (game mode).
/// - Panel = island + pad (BackEase overshoot-д). Pad хэсэг click-through байхын тулд
///   IslandController нь `ignoresMouseEvents`-ийг cursor island дээр байх үед л false болгоно.
final class IslandPanel: NSPanel {
    /// Collapsed үед false (бусад app-аас focus булаахгүй), Expanded үед true (Esc, TextField).
    var allowsKey = false

    /// Header (robot) дээр дарсан эсэхийг шалгана (screen координат).
    var isInPressRegion: (NSPoint) -> Bool = { _ in false }
    var canDrag: () -> Bool = { true }
    var onClick: (() -> Void)?
    var onDragMoved: (() -> Void)?
    var onDragEnded: (() -> Void)?

    private(set) var isPressed = false
    private(set) var isDragging = false
    private var pressPoint = NSPoint.zero
    private var pressOrigin = NSPoint.zero
    static let dragThreshold: CGFloat = 6

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
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true
    }

    /// Header дээр: дарах → (6pt-ээс их хөдөлбөл) чирэх, эс бөгөөс click. Event-ийг SwiftUI руу үргэлжлүүлнэ.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            let p = NSEvent.mouseLocation
            if isInPressRegion(p) {
                isPressed = true
                isDragging = false
                pressPoint = p
                pressOrigin = frame.origin
            }
        case .leftMouseDragged where isPressed:
            let p = NSEvent.mouseLocation
            let dx = p.x - pressPoint.x, dy = p.y - pressPoint.y
            if !isDragging, canDrag(), abs(dx) >= Self.dragThreshold || abs(dy) >= Self.dragThreshold {
                isDragging = true
            }
            if isDragging {
                setFrameOrigin(NSPoint(x: pressOrigin.x + dx, y: pressOrigin.y + dy))
                onDragMoved?()
            }
        case .leftMouseUp where isPressed:
            let dragged = isDragging
            isPressed = false
            isDragging = false
            if dragged { onDragEnded?() } else { onClick?() }
        default:
            break
        }
        super.sendEvent(event)
    }

    /// Borderless цонхыг дэлгэцийн дээд ирмэгээс доош түлхэхгүй (menu bar-ийн дээгүүр байрлана).
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}
