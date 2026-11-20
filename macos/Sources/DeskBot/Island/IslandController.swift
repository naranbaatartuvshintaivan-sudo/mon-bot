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
}

/// Island panel-ийг үүсгэж, дэлгэц/тохиргоо өөрчлөгдөхөд байрлалыг дахин тооцно.
/// M1: зөвхөн Collapsed. Hover/Expanded/Alert/drag — M3.
@MainActor
final class IslandController {
    private let settings: AppSettings
    private let model = IslandModel()
    private let panel: IslandPanel
    private var screenObserver: NSObjectProtocol?

    private(set) var isVisible = false
    var layout: IslandLayout { model.layout }

    init(settings: AppSettings) {
        self.settings = settings
        panel = IslandPanel(contentRect: NSRect(x: 0, y: 0, width: 190, height: 34))
        let host = NSHostingView(rootView: IslandView(model: model))
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

    func show() {
        isVisible = true
        relayout()
        panel.orderFrontRegardless()
    }

    func hide() {
        isVisible = false
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
