import Foundation
import Observation
import DeskBotCore

/// Local reminder-ууд (~/Library/Application Support/DeskBot/reminders.json). Cloud рүү юу ч илгээхгүй.
/// Notification Center-ийн эрх хүсэхгүй — мэдэгдэл нь island-ийн Alert mode (C# ReminderService).
@MainActor
@Observable
final class ReminderService {
    static let approachWindow: TimeInterval = 5 * 60
    static let snoozeInterval: TimeInterval = 5 * 60
    static let checkInterval: TimeInterval = 10

    private(set) var book: ReminderBook
    private(set) var lastSaveError: String?

    @ObservationIgnored let url: URL
    @ObservationIgnored var onFired: ((Reminder) -> Void)?
    @ObservationIgnored var onApproaching: ((Reminder) -> Void)?
    @ObservationIgnored var onListChanged: (() -> Void)?
    @ObservationIgnored private var timer: Timer?

    init(url: URL = SettingsStore.directory.appendingPathComponent("reminders.json")) {
        self.url = url
        var b = JSONFileStore.loadOrDefault(url) { ReminderBook() }
        b.prune(now: .now, keepDone: 30 * 86_400)
        book = b
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
        // App унтарсан хооронд хугацаа нь өнгөрсөн reminder-ууд асаахад шууд мэдэгдэнэ.
        DispatchQueue.main.async { [weak self] in self?.check() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @discardableResult
    func add(_ title: String, dueAt: Date) throws -> Reminder {
        let r = try book.add(title, dueAt: dueAt, now: .now)
        save()
        return r
    }

    func snooze(_ id: UUID) {
        try? book.snooze(id, now: .now, by: Self.snoozeInterval)
        save()
    }

    func complete(_ id: UUID) {
        try? book.complete(id)
        save()
    }

    func remove(_ id: UUID) {
        book.remove(id)
        save()
    }

    func reminder(_ id: UUID) -> Reminder? { book.items.first { $0.id == id } }

    func check(now: Date = .now) {
        let due = book.collectDue(now: now)
        let soon = book.collectApproaching(now: now, window: Self.approachWindow)
        if !due.isEmpty || !soon.isEmpty { save() }
        soon.forEach { onApproaching?($0) }
        due.forEach { onFired?($0) }
    }

    private func save() {
        do {
            try JSONFileStore.saveAtomic(url, book)
            lastSaveError = nil
        } catch {
            lastSaveError = error.localizedDescription
            Log.error("Reminder save failed: \(error)")
        }
        onListChanged?()
    }
}
