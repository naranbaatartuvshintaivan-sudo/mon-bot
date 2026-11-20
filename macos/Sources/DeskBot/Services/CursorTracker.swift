import AppKit

/// Global cursor хөдөлгөөн ба click (C#: GlobalMouseHook).
/// `NSEvent.addGlobalMonitorForEvents` нь mouse event-д Accessibility эрх ШААРДАХГҮЙ
/// (зөвхөн key event-д шаарддаг). Global monitor өөрийн app-ийн цонх дээрх event-ийг авдаггүй тул
/// local monitor-ыг давхар тавина. Байрлал л уншина — event-ийг өөрчлөхгүй, бичихгүй.
@MainActor
final class CursorTracker {
    var onMove: ((NSPoint) -> Void)?
    var onClick: ((NSPoint) -> Void)?
    /// Debug: хүлээн авсан move event-ийн тоо (log-д).
    private(set) var moveEvents = 0

    private var monitors: [Any] = []

    private static let moveMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
    private static let clickMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]

    func start() {
        guard monitors.isEmpty else { return }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: Self.moveMask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.moved() }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: Self.moveMask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.moved() }
            return event
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: Self.clickMask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.onClick?(NSEvent.mouseLocation) }
        }) { monitors.append(m) }
        moved() // эхний байрлал
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func moved() {
        moveEvents += 1
        onMove?(NSEvent.mouseLocation)
    }
}
