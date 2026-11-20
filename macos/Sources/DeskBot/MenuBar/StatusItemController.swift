import AppKit

/// Menu bar icon (хар pill + 2 cyan нүд, code-оор зурсан) ба цэс.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let isIslandVisible: () -> Bool
    private let toggleIsland: () -> Void
    private let resetPosition: () -> Void
    private let quit: () -> Void
    private let toggleItem = NSMenuItem(title: "Hide DeskBot", action: nil, keyEquivalent: "")

    init(isIslandVisible: @escaping () -> Bool, toggleIsland: @escaping () -> Void,
         resetPosition: @escaping () -> Void, quit: @escaping () -> Void) {
        self.isIslandVisible = isIslandVisible
        self.toggleIsland = toggleIsland
        self.resetPosition = resetPosition
        self.quit = quit
        super.init()

        item.button?.image = Self.makeIcon()
        item.button?.toolTip = "DeskBot"

        let menu = NSMenu()
        menu.delegate = self
        toggleItem.action = #selector(onToggle)
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(make("Reset Position", #selector(onReset)))
        menu.addItem(.separator())
        menu.addItem(make("Quit DeskBot", #selector(onQuit), key: "q"))
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        toggleItem.title = isIslandVisible() ? "Hide DeskBot" : "Show DeskBot"
    }

    private func make(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let m = NSMenuItem(title: title, action: action, keyEquivalent: key)
        m.target = self
        return m
    }

    @objc private func onToggle() { toggleIsland() }
    @objc private func onReset() { resetPosition() }
    @objc private func onQuit() { quit() }

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
