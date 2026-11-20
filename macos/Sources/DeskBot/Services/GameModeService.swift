import AppKit
import CoreGraphics
import DeskBotCore

/// Game mode — island-ийн дэлгэц дээр өөр app-ийн цонх дэлгэцийг бүтэн хучвал (borderless fullscreen
/// тоглоом, видео, presentation) island нуугдаж face зогсоно. Native fullscreen Space-д island угаасаа
/// харагдахгүй (`.fullScreenAuxiliary`-гүй), тэр үед face-ийг panel-ийн occlusion-оор зогсооно.
/// `CGWindowListCopyWindowInfo`-ийн bounds/layer/PID нь Screen Recording эрх шаарддаггүй (цонхны нэр уншихгүй).
@MainActor
final class GameModeService {
    static let interval: TimeInterval = 1.5

    var screen: () -> NSScreen? = { NSScreen.main }
    var onChange: ((Bool) -> Void)?
    private(set) var isFullscreen = false
    private var timer: Timer?

    func setEnabled(_ on: Bool) {
        if on {
            guard timer == nil else { return }
            let t = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            }
            t.tolerance = 0.3
            RunLoop.main.add(t, forMode: .common)
            timer = t
            check()
        } else {
            timer?.invalidate()
            timer = nil
            update(false)
        }
    }

    func check() {
        guard let screen = screen(), let primary = NSScreen.screens.first else { return update(false) }
        let screenCG = FullscreenDetector.cgRect(ofCocoa: screen.frame, primaryHeight: primary.frame.height)
        update(FullscreenDetector.isFullscreen(windows: Self.windows(), screenCG: screenCG,
                                               selfPID: ProcessInfo.processInfo.processIdentifier))
    }

    private func update(_ fs: Bool) {
        guard fs != isFullscreen else { return }
        isFullscreen = fs
        Log.info("Game mode: fullscreen \(fs ? "detected → hide" : "ended → show")")
        onChange?(fs)
    }

    static func windows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { d in
            guard let pid = d[kCGWindowOwnerPID as String] as? Int32,
                  let layer = d[kCGWindowLayer as String] as? Int,
                  let b = d[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: b) else { return nil }
            return WindowInfo(ownerPID: pid, layer: layer, bounds: rect,
                              alpha: (d[kCGWindowAlpha as String] as? Double) ?? 1)
        }
    }
}
