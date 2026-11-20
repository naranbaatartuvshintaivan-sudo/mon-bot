import AppKit
import DeskBotCore

@main
@MainActor
enum DeskBotMain {
    static func main() {
        let app = NSApplication.shared
        // Unbundled executable-д LSUIElement үйлчлэхгүй тул энд тавина (Dock icon, app menu-гүй).
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsStore: SettingsStore!
    private var island: IslandController!
    private var statusItem: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        settingsStore = SettingsStore()
        island = IslandController(settings: settingsStore.settings)
        statusItem = StatusItemController(
            isIslandVisible: { [unowned self] in island.isVisible },
            toggleIsland: { [unowned self] in island.toggleVisible() },
            resetPosition: { [unowned self] in island.resetPosition() },
            quit: { NSApp.terminate(nil) })
        island.show()
        Log.info("DeskBot started (notch: \(island.layout.hasNotch), frame: \(NSStringFromRect(island.layout.frame)))")
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        settingsStore.flush()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.info("DeskBot quit")
    }
}
