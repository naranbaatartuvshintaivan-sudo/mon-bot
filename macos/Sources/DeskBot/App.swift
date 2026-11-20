import AppKit
import DeskBotCore

@main
@MainActor
enum DeskBotMain {
    static func main() {
        // Debug: `DeskBot --render-faces out.png` — бүх expression-ийг offscreen зураад гарна.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-faces"), i + 1 < args.count {
            do {
                try FaceSheetExporter.export(to: URL(fileURLWithPath: args[i + 1]))
                print("Wrote \(args[i + 1])")
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("render failed: \(error)\n".utf8))
                exit(1)
            }
        }

        if let i = args.firstIndex(of: "--render-island"), i + 1 < args.count {
            do {
                try IslandSheetExporter.export(to: URL(fileURLWithPath: args[i + 1]))
                print("Wrote \(args[i + 1])")
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("render failed: \(error)\n".utf8))
                exit(1)
            }
        }

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
    private var face: FaceDriver!
    private var brain: CompanionBrain!
    private var cursor: CursorTracker!
    private var island: IslandController!
    private var statusItem: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        settingsStore = SettingsStore()
        let settings = settingsStore.settings

        face = FaceDriver(settings: settings)
        island = IslandController(settings: settings, face: face)

        brain = CompanionBrain(settings: settings)
        brain.onExpression = { [unowned self] e in face.setExpression(e) }
        brain.isCursorNear = { [unowned self] in face.isCursorNear }
        face.setExpression(brain.current)
        island.onFaceClick = { [unowned self] in
            brain.click()
            face.pulse()
        }

        cursor = CursorTracker()
        cursor.onMove = { [unowned self] p in face.setCursor(screen: p, faceCenter: island.faceCenterOnScreen) }
        cursor.onClick = { [unowned self] p in
            let canGlance = island.globalClick(at: p) // гадна click → Expanded хаагдана (pin-гүй бол)
            guard settings.reactToGlobalClicks, canGlance else { return }
            face.glance(screen: p, faceCenter: island.faceCenterOnScreen)
        }

        statusItem = StatusItemController(
            settings: settings,
            island: island,
            currentExpression: { [unowned self] in brain.current },
            previewExpression: { [unowned self] e in
                brain.preview(e)
                Log.info("Expression preview: \(e.rawValue) → current \(brain.current.rawValue)")
            },
            quit: { NSApp.terminate(nil) })

        island.show()
        cursor.start()
        brain.start()
        Log.info("DeskBot started (notch: \(island.layout.hasNotch), frame: \(NSStringFromRect(island.layout.frame)))")
        startDebugHeartbeat()
    }

    /// `DESKBOT_DEBUG_FACE=1`: 5с тутам face төлөвийг log-д бичнэ (cursor event ирж байгааг шалгах).
    private func startDebugHeartbeat() {
        guard ProcessInfo.processInfo.environment["DESKBOT_DEBUG_FACE"] == "1" else { return }
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let a = self.face.animator
                Log.info(String(format: "face t=%.1f expr=%@ look=(%.2f,%.2f) notice=%.2f blink=%.2f moves=%d near=%@",
                                a.time, a.expression.rawValue, a.look.x, a.look.y, a.notice, a.blinkOpenness,
                                self.cursor.moveEvents, a.isCursorNear ? "yes" : "no"))
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        cursor.stop()
        brain.stop()
        settingsStore.flush()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.info("DeskBot quit")
    }
}
