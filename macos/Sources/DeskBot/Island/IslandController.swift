import AppKit
import Observation
import SwiftUI
import DeskBotCore

/// Island-ийн харагдах төлөв (SwiftUI view үүнийг уншина).
@MainActor
@Observable
final class IslandModel {
    var layout = IslandLayout(frame: .zero, notchInIsland: nil)
    var cornerRadius: CGFloat = 18
    var simulatedNotch = false
    /// false бол face animation зогсоно (CPU хэмнэнэ).
    var faceVisible = false
}

/// Island panel-ийг үүсгэж, дэлгэц/тохиргоо өөрчлөгдөхөд байрлалыг дахин тооцно.
/// M1–M2: зөвхөн Collapsed (robot нүүртэй). Hover/Expanded/Alert/drag — M3.
@MainActor
final class IslandController {
    private let settings: AppSettings
    private let model = IslandModel()
    private let panel: IslandPanel
    private var screenObserver: NSObjectProtocol?

    private(set) var isVisible = false
    var layout: IslandLayout { model.layout }

    private let face: FaceDriver

    init(settings: AppSettings, face: FaceDriver) {
        self.settings = settings
        self.face = face
        panel = IslandPanel(contentRect: NSRect(x: 0, y: 0, width: 190, height: 34))
        let host = NSHostingView(rootView: IslandView(model: model, face: face))
        host.sizingOptions = [] // panel-ийн хэмжээг бид удирдана
        panel.contentView = host

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.relayout() }
        }
        observeSettings()
        relayout()
    }

    /// Face-ийн төв (Cocoa screen координат, y дээшээ). Face нь island-ийн төвд байрлана.
    var faceCenterOnScreen: NSPoint { NSPoint(x: panel.frame.midX, y: panel.frame.midY) }

    /// Robot (island) дээр click хийхэд.
    var onClick: (() -> Void)? {
        get { panel.onClick }
        set { panel.onClick = newValue }
    }

    func show() {
        isVisible = true
        relayout()
        face.resetClock()
        model.faceVisible = true
        panel.orderFrontRegardless()
    }

    func hide() {
        isVisible = false
        model.faceVisible = false
        panel.orderOut(nil)
    }

    func toggleVisible() { isVisible ? hide() : show() }

    func resetPosition() {
        settings.offsetX = 0
        settings.topOffset = 0
        settings.monitorID = ""
    }

    private func observeSettings() {
        withObservationTracking {
            _ = (settings.islandWidth, settings.islandHeight, settings.topOffset,
                 settings.offsetX, settings.monitorID, settings.cornerRadius)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.relayout()
                self?.observeSettings()
            }
        }
    }

    private func relayout() {
        guard let screen = ScreenProvider.screen(for: settings.monitorID) else { return }
        let geo = ScreenProvider.geometry(of: screen)
        let l = IslandLayout.collapsed(screen: geo,
                                       width: settings.islandWidth, height: settings.islandHeight,
                                       topOffset: settings.topOffset, offsetX: settings.offsetX)
        model.layout = l
        model.cornerRadius = settings.cornerRadius
        model.simulatedNotch = ScreenProvider.simulateNotch && l.hasNotch
        if panel.frame != l.frame {
            panel.setFrame(l.frame, display: true)
        }
    }
}
