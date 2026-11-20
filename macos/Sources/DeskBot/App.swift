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
    private var previewFace: FaceDriver!
    private var brain: CompanionBrain!
    private var cursor: CursorTracker!
    private var island: IslandController!
    private var statusItem: StatusItemController!
    private var reminders: ReminderService!
    private var system: SystemMonitor!
    private var hotkey: HotkeyService!
    private var gameMode: GameModeService!
    private let expression = ExpressionState()

    /// Reminder alert queue (C# _alerts / _currentAlert).
    private var alertQueue: [UUID] = []
    private var currentAlert: UUID?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settingsStore = SettingsStore()
        let settings = settingsStore.settings

        face = FaceDriver(settings: settings)
        previewFace = FaceDriver(settings: settings)
        reminders = ReminderService()
        system = SystemMonitor()
        hotkey = HotkeyService()
        gameMode = GameModeService()
        brain = CompanionBrain(settings: settings)

        var deps = ControlCenterDeps(settings: settings, reminders: reminders, system: system,
                                     expression: expression, previewFace: previewFace)
        deps.preview = { [unowned self] e in brain.preview(e) }
        deps.applyHotkey = { [unowned self] text in applyHotkey(text) }
        deps.resetPosition = { [unowned self] in island.resetPosition() }
        island = IslandController(settings: settings, face: face, deps: deps)

        // Expression → хоёр face (island + Face tab preview) + label
        brain.onExpression = { [unowned self] e in
            face.setExpression(e)
            previewFace.setExpression(e)
            expression.current = e
        }
        brain.isCursorNear = { [unowned self] in face.isCursorNear }
        face.setExpression(brain.current)
        previewFace.setExpression(brain.current)
        expression.current = brain.current
        island.onFaceClick = { [unowned self] in
            brain.click()
            face.pulse()
        }
        island.onModeChange = { [unowned self] mode in system.setFast(mode == .expanded) }

        // Reminders → brain + Alert mode
        reminders.onApproaching = { [unowned self] _ in brain.reminderApproaching() }
        reminders.onFired = { [unowned self] r in
            brain.reminderFired()
            alertQueue.append(r.id)
            showNextAlert()
        }
        reminders.onListChanged = { [unowned self] in
            brain.syncReminders(hasFiredPending: reminders.book.hasFiredPending)
            dropResolvedAlerts()
        }
        island.onAlertFinished = { [unowned self] snoozed in
            Log.info("Reminder alert \(snoozed ? "snoozed" : "done")")
            if let id = currentAlert { snoozed ? reminders.snooze(id) : reminders.complete(id) }
            currentAlert = nil
            showNextAlert()
        }

        system.onUpdate = { [unowned self] in brain.battery(system.battery) }

        hotkey.onPressed = { [unowned self] in island.toggleControlCenter() }

        gameMode.screen = { ScreenProvider.screen(for: settings.dockScreen) }
        gameMode.onChange = { [unowned self] fs in
            island.setGameHidden(fs)
            if !fs { showNextAlert() }
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
            hotkeySymbols: { [unowned self] in hotkey.current?.symbols },
            currentExpression: { [unowned self] in brain.current },
            previewExpression: { [unowned self] e in brain.preview(e) },
            quit: { NSApp.terminate(nil) })

        island.show()
        // Bench: `DESKBOT_BENCH_STILL=1` — cursor event авахгүй (хөдөлгөөнгүй mouse-ийг дуурайж idle CPU хэмжинэ).
        if ProcessInfo.processInfo.environment["DESKBOT_BENCH_STILL"] != "1" { cursor.start() }
        brain.start()
        system.start()
        reminders.start()
        if let err = applyHotkey(settings.hotkey) { Log.error("Hotkey: \(err)") }
        gameMode.setEnabled(settings.gameModeAutoHide)
        reconcileLoginItem(settings)
        observeSettings(settings)
        Log.info("DeskBot started (notch: \(island.layout.hasNotch), frame: \(NSStringFromRect(island.layout.frame)))")
        startDebugHeartbeat()
    }

    // MARK: - Alerts

    private func showNextAlert() {
        guard currentAlert == nil else { return }
        while let id = alertQueue.first {
            alertQueue.removeFirst()
            guard let r = reminders.reminder(id), r.fired, !r.done else { continue }
            currentAlert = id
            Log.info("Reminder alert shown (expression: \(brain.current.rawValue))")
            // Game mode-д нуугдсан бол mode-ийг Alert болгоод үлдээнэ — fullscreen дуусахад гарна.
            island.showAlert(title: r.title, time: r.dueAt)
            return
        }
        if island.isShowingAlert { island.endAlert() }
    }

    /// Reminders tab-аас Done/устгасан бол alert-ийг цэвэрлэнэ.
    private func dropResolvedAlerts() {
        alertQueue.removeAll { id in reminders.reminder(id).map { $0.done || !$0.fired } ?? true }
        if let id = currentAlert, reminders.reminder(id).map({ $0.done || !$0.fired }) ?? true {
            currentAlert = nil
            showNextAlert()
        }
    }

    // MARK: - Settings side effects

    @discardableResult
    private func applyHotkey(_ text: String) -> String? {
        if let err = hotkey.register(text) { return err }
        if let spec = hotkey.current { settingsStore.settings.hotkey = spec.description }
        return nil
    }

    /// settings.startAtLogin нь хэрэглэгчийн хүсэл. Bundle хийсэн app-д SMAppService-тэй тааруулна.
    private func reconcileLoginItem(_ s: AppSettings) {
        guard LoginItemService.isBundled, s.startAtLogin != LoginItemService.isEnabled else { return }
        if let err = LoginItemService.set(s.startAtLogin) { Log.error("Login item: \(err)") }
    }

    private func observeSettings(_ s: AppSettings) {
        withObservationTracking {
            _ = s.gameModeAutoHide
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let s = self.settingsStore.settings
                self.gameMode.setEnabled(s.gameModeAutoHide)
                self.observeSettings(s)
            }
        }
    }

    /// `DESKBOT_DEBUG_FACE=1`: 5с тутам face төлөвийг log-д бичнэ (cursor event ирж байгааг шалгах).
    private func startDebugHeartbeat() {
        guard ProcessInfo.processInfo.environment["DESKBOT_DEBUG_FACE"] == "1" else { return }
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let a = self.face.animator
                Log.info(String(format: "face t=%.1f demand=%d expr=%@ look=(%.2f,%.2f) notice=%.2f blink=%.2f moves=%d near=%@ frames=%d",
                                a.time, a.frameDemand.rawValue, a.expression.rawValue, a.look.x, a.look.y, a.notice, a.blinkOpenness,
                                self.cursor.moveEvents, a.isCursorNear ? "yes" : "no", RobotFaceNSView.framesDrawn))
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        cursor.stop()
        brain.stop()
        system.stop()
        reminders.stop()
        hotkey.unregister()
        gameMode.setEnabled(false)
        settingsStore.flush()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.info("DeskBot quit")
    }
}
