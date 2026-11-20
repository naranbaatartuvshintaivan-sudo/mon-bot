import CoreGraphics
import Foundation
import Observation
import DeskBotCore

/// Automation rules → ExpressionStateMachine (C# порт: src/DeskBot.App/Services/CompanionBrain.cs).
/// - Reminder 5 мин дутуу → ActiveTask Reminder 3с; цаг болсон → Reminder (Done/Snooze хүртэл)
/// - Battery ≤ 15% & цэнэглээгүй → SystemStatus LowBattery
/// - 5 мин idle → Ambient Sleepy; click → Surprised 450ms; Face tab preview → Preview (45) 3с
/// - Spotify / Apple Music тоглож байна → Music (20); зогсвол цэвэрлэнэ.
@MainActor
final class CompanionBrain {
    static let idleSleepSeconds: TimeInterval = 5 * 60
    /// Cursor face-ийн ойролцоо байх үед Cursor layer-ийг энэ хугацаагаар сунгана.
    static let cursorHoldSeconds: TimeInterval = 1.5
    static let previewSeconds: TimeInterval = 3

    let machine = ExpressionStateMachine()
    var onExpression: ((RobotExpression) -> Void)?
    /// FaceDriver-ээс: cursor face төвөөс 170pt дотор уу.
    var isCursorNear: () -> Bool = { false }

    private let settings: AppSettings
    private var timer: Timer?
    private var idleCounter = 0

    init(settings: AppSettings) {
        self.settings = settings
        machine.onChange = { [weak self] e in self?.onExpression?(e) }
        machine.setBaseMood(settings.baseMood, now: .now) // ANGRY → Idle (sanitize)
        observeBaseMood()
    }

    var current: RobotExpression { machine.current }

    func start() {
        guard timer == nil else { return }
        // C#: DispatcherTimer 150ms
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Robot дээр click → Surprised 450ms (C#: CompanionBrain.Click).
    static let clickSeconds: TimeInterval = 0.45

    func click() {
        machine.set(.userClick, .surprised, now: .now, duration: Self.clickSeconds)
    }

    /// Face tab / debug цэс: expression-ийг Preview layer (45)-ээр 3с түр тавина.
    func preview(_ e: RobotExpression) {
        machine.set(.preview, e, now: .now, duration: Self.previewSeconds)
    }

    /// C#: Approaching → ActiveTask Reminder 3с.
    func reminderApproaching() {
        machine.set(.activeTask, .reminder, now: .now, duration: 3)
    }

    /// C#: Fired → Reminder layer (Done/Snooze хүртэл).
    func reminderFired() {
        machine.set(.reminder, .reminder, now: .now)
    }

    /// C# SyncReminderLayer: дууссан/snooze хийсэн бол Reminder layer-ийг цэвэрлэнэ.
    func syncReminders(hasFiredPending: Bool) {
        if !hasFiredPending { machine.clear(.reminder, now: .now) }
    }

    func media(_ status: MediaStatus) {
        if MediaPolicy.wantsMusicExpression(status) {
            machine.set(.music, .music, now: .now)
        } else {
            machine.clear(.music, now: .now)
        }
    }

    func battery(_ b: BatteryState) {
        if CompanionRules.isBatteryLow(b) {
            machine.set(.systemStatus, .lowBattery, now: .now)
        } else {
            machine.clear(.systemStatus, now: .now)
        }
    }

    private func tick() {
        let now = Date()

        // Cursor (10): cursor ойрхон байх хооронд Happy. (C#-д Cursor layer ашиглагдаагүй — M2-ийн шинэ дүрэм.)
        if isCursorNear() {
            machine.set(.cursor, .happy, now: now, duration: Self.cursorHoldSeconds)
        }

        // Ambient (5): ~3с тутам idle шалгана. 5 мин хөдөлгөөнгүй → Sleepy.
        idleCounter += 1
        if idleCounter >= 20 {
            idleCounter = 0
            if settings.sleepWhenIdle && Self.systemIdleSeconds() > Self.idleSleepSeconds {
                machine.set(.ambient, .sleepy, now: now)
            } else {
                machine.clear(.ambient, now: now)
            }
        }

        machine.tick(now: now)
    }

    /// Сүүлийн гар/mouse оролтоос хойшхи хугацаа. Эрх шаардахгүй (event агуулга уншихгүй).
    static func systemIdleSeconds() -> TimeInterval {
        guard let any = CGEventType(rawValue: ~0) else { return 0 } // kCGAnyInputEventType
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
    }

    private func observeBaseMood() {
        withObservationTracking {
            _ = settings.baseMood
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.machine.setBaseMood(self.settings.baseMood, now: .now)
                self.observeBaseMood()
            }
        }
    }
}
