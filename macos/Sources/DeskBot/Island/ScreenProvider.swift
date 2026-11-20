import AppKit
import DeskBotCore

/// NSScreen → `ScreenGeometry`. Notch-гүй Mac дээр notch замыг турших бол
/// `DESKBOT_SIMULATE_NOTCH=1` (185pt өргөн, menu bar өндөртэй хуурамч notch).
@MainActor
enum ScreenProvider {
    static let simulateNotch = ProcessInfo.processInfo.environment["DESKBOT_SIMULATE_NOTCH"] == "1"

    /// Тохиргооны dockScreen-тай таарах дэлгэц, эс бөгөөс menu bar-тай үндсэн дэлгэц.
    static func screen(for dockScreen: String) -> NSScreen? {
        let screens = NSScreen.screens
        if !dockScreen.isEmpty, let s = screens.first(where: { id(of: $0) == dockScreen }) { return s }
        return screens.first
    }

    static func id(of screen: NSScreen) -> String {
        if let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return "\(screen.localizedName)#\(n.uint32Value)"
        }
        return screen.localizedName
    }

    static func geometry(of screen: NSScreen) -> ScreenGeometry {
        let f = screen.frame
        if simulateNotch, screen.safeAreaInsets.top == 0 {
            let menuBar = max(f.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
            let w: CGFloat = 185
            let left = CGRect(x: f.minX, y: f.maxY - menuBar, width: (f.width - w) / 2, height: menuBar)
            let right = CGRect(x: left.maxX + w, y: left.minY, width: left.width, height: menuBar)
            return ScreenGeometry(frame: f, safeAreaTop: menuBar, auxiliaryTopLeft: left, auxiliaryTopRight: right)
        }
        return ScreenGeometry(frame: f,
                              safeAreaTop: screen.safeAreaInsets.top,
                              auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
                              auxiliaryTopRight: screen.auxiliaryTopRightArea)
    }
}
