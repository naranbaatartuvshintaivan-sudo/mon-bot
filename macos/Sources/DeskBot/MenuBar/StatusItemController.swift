import AppKit
import DeskBotCore

/// Menu bar icon (хар pill + 2 cyan нүд, code-оор зурсан) ба цэс.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let settings: AppSettings
    private let island: IslandController
    private let hotkeySymbols: () -> String?
    private let quit: () -> Void
    private let currentExpression: () -> RobotExpression
    private let previewExpression: (RobotExpression) -> Void

    private let menu = NSMenu()
    private let toggleItem = NSMenuItem(title: "Hide DeskBot", action: nil, keyEquivalent: "")
    private let centerItem = NSMenuItem(title: "Open Control Center", action: nil, keyEquivalent: "")
    private let pinItem = NSMenuItem(title: "Pin Control Center", action: nil, keyEquivalent: "")
    private let autoHideItem = NSMenuItem(title: "Auto-hide", action: nil, keyEquivalent: "")
    private let lockItem = NSMenuItem(title: "Lock Position", action: nil, keyEquivalent: "")
    private let displayMenu = NSMenu(title: "Display")
    private let expressionMenu = NSMenu(title: "Expression")

    init(settings: AppSettings, island: IslandController,
         hotkeySymbols: @escaping () -> String?,
         currentExpression: @escaping () -> RobotExpression,
         previewExpression: @escaping (RobotExpression) -> Void,
         quit: @escaping () -> Void) {
        self.settings = settings
        self.island = island
        self.hotkeySymbols = hotkeySymbols
        self.currentExpression = currentExpression
        self.previewExpression = previewExpression
        self.quit = quit
        super.init()

        item.button?.image = Self.makeIcon()
        item.button?.toolTip = "DeskBot"

        menu.delegate = self
        for (m, sel) in [(toggleItem, #selector(onToggle)), (centerItem, #selector(onCenter)),
                         (pinItem, #selector(onPin)), (autoHideItem, #selector(onAutoHide)),
                         (lockItem, #selector(onLock))] {
            m.action = sel
            m.target = self
        }
        menu.addItem(toggleItem)
        menu.addItem(centerItem)
        menu.addItem(.separator())
        menu.addItem(pinItem)
        menu.addItem(autoHideItem)
        menu.addItem(lockItem)
        displayMenu.delegate = self
        let displayItem = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
        displayItem.submenu = displayMenu
        menu.addItem(displayItem)
        menu.addItem(make("Reset Position", #selector(onReset)))
        menu.addItem(.separator())

        // Debug: бүх expression-ийг UserClick layer-ээр 3с түр тавьж турших.
        expressionMenu.delegate = self
        for e in RobotExpression.allCases {
            let m = make(e.rawValue, #selector(onExpression(_:)))
            m.representedObject = e.rawValue
            expressionMenu.addItem(m)
        }
        let expressionItem = NSMenuItem(title: "Expression", action: nil, keyEquivalent: "")
        expressionItem.submenu = expressionMenu
        menu.addItem(expressionItem)
        menu.addItem(.separator())
        menu.addItem(make("Quit DeskBot", #selector(onQuit), key: "q"))
        item.menu = menu
    }

    func menuNeedsUpdate(_ m: NSMenu) {
        if m === expressionMenu {
            let current = currentExpression().rawValue
            for item in m.items {
                item.state = (item.representedObject as? String) == current ? .on : .off
            }
        } else if m === displayMenu {
            rebuildDisplayMenu()
        } else {
            toggleItem.title = island.isVisible ? "Hide DeskBot" : "Show DeskBot"
            let title = island.mode == .expanded ? "Close Control Center" : "Open Control Center"
            centerItem.title = hotkeySymbols().map { "\(title)  (\($0))" } ?? title
            pinItem.state = settings.pinned ? .on : .off
            autoHideItem.state = settings.autoHide ? .on : .off
            lockItem.state = settings.lockPosition ? .on : .off
        }
    }

    /// Холбогдсон дэлгэцүүд. "Main Display" = dockScreen "" (menu bar-тай дэлгэц).
    private func rebuildDisplayMenu() {
        displayMenu.removeAllItems()
        let main = make("Main Display", #selector(onDisplay(_:)))
        main.representedObject = ""
        main.state = settings.dockScreen.isEmpty ? .on : .off
        displayMenu.addItem(main)
        displayMenu.addItem(.separator())
        for screen in NSScreen.screens {
            let id = ScreenProvider.id(of: screen)
            let m = make(screen.localizedName, #selector(onDisplay(_:)))
            m.representedObject = id
            m.state = settings.dockScreen == id ? .on : .off
            displayMenu.addItem(m)
        }
    }

    private func make(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let m = NSMenuItem(title: title, action: action, keyEquivalent: key)
        m.target = self
        return m
    }

    @objc private func onToggle() { island.toggleVisible() }
    @objc private func onCenter() { island.toggleControlCenter() }
    @objc private func onPin() { settings.pinned.toggle() }
    @objc private func onAutoHide() { settings.autoHide.toggle() }
    @objc private func onLock() { settings.lockPosition.toggle() }
    @objc private func onReset() { island.resetPosition() }
    @objc private func onQuit() { quit() }
    @objc private func onDisplay(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        // Шинэ дэлгэц дээр дээд төвөөс эхэлнэ (өөр хэмжээтэй дэлгэцэд offset утгагүй).
        settings.offsetX = 0
        settings.topOffset = 0
        settings.dockScreen = id
    }
    @objc private func onExpression(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let e = RobotExpression(rawValue: raw) else { return }
        previewExpression(e)
    }

    /// 22×14pt: хар pill (цагаан хүрээтэй — хар menu bar дээр ч харагдана) + 2 cyan нүд.
    static func makeIcon() -> NSImage {
        let size = NSSize(width: 22, height: 14)
        let img = NSImage(size: size, flipped: false) { rect in
            let pill = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 6.5, yRadius: 6.5)
            NSColor.black.setFill()
            pill.fill()
            NSColor.white.withAlphaComponent(0.35).setStroke()
            pill.lineWidth = 1
            pill.stroke()
            let cyan = NSColor(srgbRed: 0x33 / 255, green: 0xE1 / 255, blue: 1, alpha: 1)
            cyan.setFill()
            for x in [7.0, 12.0] {
                NSBezierPath(roundedRect: NSRect(x: x, y: 4, width: 3, height: 6), xRadius: 1.2, yRadius: 1.2).fill()
            }
            return true
        }
        img.isTemplate = false
        img.accessibilityDescription = "DeskBot"
        return img
    }
}
