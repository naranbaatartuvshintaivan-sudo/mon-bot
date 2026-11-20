import Foundation
import Observation
import Testing
@testable import DeskBotCore

// C# порт: tests/DeskBot.Core.Tests/ReminderAndSettingsTests.cs

private let now = T0
private func minutes(_ m: Double) -> TimeInterval { m * 60 }

@Suite struct ReminderBookTests {
    @Test func rejectsPastAndEmpty() {
        var book = ReminderBook()
        #expect(throws: ReminderError.dueInPast) { try book.add("x", dueAt: now - minutes(1), now: now) }
        #expect(throws: ReminderError.emptyTitle) { try book.add("  ", dueAt: now + minutes(5), now: now) }
    }

    @Test func dueFiresExactlyOnce() throws {
        var book = ReminderBook()
        try book.add("Pull-ups", dueAt: now + minutes(10), now: now)
        #expect(book.collectDue(now: now + minutes(5)).isEmpty)
        #expect(book.collectDue(now: now + minutes(10)).count == 1)
        #expect(book.collectDue(now: now + minutes(11)).isEmpty)
    }

    @Test func snoozeReschedulesAndRefires() throws {
        var book = ReminderBook()
        let r = try book.add("Call", dueAt: now + minutes(1), now: now)
        _ = book.collectDue(now: now + minutes(1))
        try book.snooze(r.id, now: now + minutes(1), by: minutes(10))
        #expect(book.collectDue(now: now + minutes(5)).isEmpty)
        #expect(book.collectDue(now: now + minutes(11)).count == 1)
    }

    @Test func approachingReportsOnce() throws {
        var book = ReminderBook()
        try book.add("Meeting", dueAt: now + minutes(4), now: now)
        #expect(book.collectApproaching(now: now, window: minutes(5)).count == 1)
        #expect(book.collectApproaching(now: now + minutes(1), window: minutes(5)).isEmpty)
    }

    @Test func completedNotUpcoming() throws {
        var book = ReminderBook()
        let r = try book.add("A", dueAt: now + minutes(60), now: now)
        try book.complete(r.id)
        #expect(book.nextUpcoming(now: now) == nil)
    }

    @Test func onDateUsesTimezone() throws {
        var book = ReminderBook()
        // 23:30 UB time = 15:30 UTC same day
        let ub = TimeZone(secondsFromGMT: 8 * 3600)!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = ub
        let late = cal.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 23, minute: 30))!
        try book.add("Late", dueAt: late, now: now)
        #expect(book.onDate(CalendarDay(year: 2026, month: 11, day: 18), in: ub).count == 1)
        #expect(book.onDate(CalendarDay(year: 2026, month: 11, day: 19), in: ub).isEmpty)
    }
}

@Suite struct SettingsTests {
    @Test func sanitizeClampsBadValues() {
        let s = AppSettings()
        s.eyeSize = 50
        s.baseMood = .angry
        s.customColor = "red"
        s.hotkey = ""
        s.sanitize()
        #expect(s.eyeSize == 1.6)
        #expect(s.baseMood == .idle)
        #expect(s.customColor == "#33E1FF")
        #expect(s.hotkey == AppSettings.defaultHotkey)
    }

    @Test func roundtripAndCorruptionFallback() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("deskbot-test-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("settings.json")
        defer { try? fm.removeItem(at: dir) }

        let original = AppSettings()
        original.theme = .matrix
        original.eyeSize = 1.3
        try JSONFileStore.saveAtomic(url, original)
        // Хоёр дахь save нь replaceItemAt замыг шалгана
        try JSONFileStore.saveAtomic(url, original)

        let loaded = JSONFileStore.loadOrDefault(url) { AppSettings() }
        #expect(loaded.theme == .matrix)
        #expect(loaded.eyeSize == 1.3)
        #expect(try String(contentsOf: url, encoding: .utf8).contains("\"Matrix\"")) // enum string-ээр

        try "{ not json".write(to: url, atomically: true, encoding: .utf8)
        let fallback = JSONFileStore.loadOrDefault(url) { AppSettings() }
        #expect(fallback.theme == .classic)
        let backups = try fm.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("settings.json.corrupt-") }
        #expect(backups.count == 1)
    }

    @Test func propertyChangeObservedForLivePreview() {
        final class Flag: @unchecked Sendable { var fired = false }
        let s = AppSettings()
        let flag = Flag()
        withObservationTracking {
            _ = s.theme
        } onChange: {
            flag.fired = true
        }
        s.theme = .aurora
        #expect(flag.fired)
    }
}
