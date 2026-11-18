import Foundation

// C# порт: src/DeskBot.Core/Reminders/ReminderBook.cs

public struct Reminder: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var title: String = ""
    public var dueAt: Date
    public var createdAt: Date
    public var done = false
    /// Notification аль хэдийн гарсан эсэх (snooze хийвэл false болно).
    public var fired = false
    /// "Ойртож байна" анхааруулга гарсан эсэх.
    public var previewed = false

    public init(id: UUID = UUID(), title: String, dueAt: Date, createdAt: Date) {
        self.id = id
        self.title = title
        self.dueAt = dueAt
        self.createdAt = createdAt
    }
}

/// Хуанлийн өдөр (C# DateOnly).
public struct CalendarDay: Hashable, Codable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int
    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, in tz: TimeZone) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let c = cal.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }
}

public enum ReminderError: Error, Equatable {
    case emptyTitle
    case dueInPast
    case notFound(UUID)
}

/// Reminder-уудын цэвэр логик — UI, timer, файлаас хамааралгүй (test хийхэд амар).
/// Value type: `ReminderStore` (app) үүнийг эзэмшиж, өөрчлөлт бүрийн дараа хадгална.
public struct ReminderBook: Codable, Sendable {
    public var items: [Reminder] = []

    public init(items: [Reminder] = []) { self.items = items }

    @discardableResult
    public mutating func add(_ title: String, dueAt: Date, now: Date) throws -> Reminder {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { throw ReminderError.emptyTitle }
        if dueAt <= now { throw ReminderError.dueInPast }
        let r = Reminder(title: title, dueAt: dueAt, createdAt: now)
        items.append(r)
        return r
    }

    /// Хугацаа нь болсон, хараахан мэдэгдээгүй reminder-уудыг буцааж fired болгоно.
    public mutating func collectDue(now: Date) -> [Reminder] {
        var due: [Reminder] = []
        for i in items.indices where !items[i].done && !items[i].fired && items[i].dueAt <= now {
            items[i].fired = true
            due.append(items[i])
        }
        return due.sorted { $0.dueAt < $1.dueAt }
    }

    /// window дотор ойртож буй, preview хараахан гараагүй reminder-ууд.
    public mutating func collectApproaching(now: Date, window: TimeInterval) -> [Reminder] {
        var list: [Reminder] = []
        for i in items.indices {
            let r = items[i]
            if !r.done && !r.fired && !r.previewed && r.dueAt > now && r.dueAt.timeIntervalSince(now) <= window {
                items[i].previewed = true
                list.append(items[i])
            }
        }
        return list
    }

    public func nextUpcoming(now: Date) -> Reminder? {
        items.filter { !$0.done && $0.dueAt > now }.min { $0.dueAt < $1.dueAt }
    }

    public var active: [Reminder] {
        items.filter { !$0.done }.sorted { $0.dueAt < $1.dueAt }
    }

    public var hasFiredPending: Bool { items.contains { $0.fired && !$0.done } }

    public mutating func snooze(_ id: UUID, now: Date, by: TimeInterval) throws {
        let i = try index(of: id)
        items[i].dueAt = now.addingTimeInterval(by)
        items[i].fired = false
        items[i].previewed = true
    }

    public mutating func complete(_ id: UUID) throws {
        items[try index(of: id)].done = true
    }

    @discardableResult
    public mutating func remove(_ id: UUID) -> Bool {
        let before = items.count
        items.removeAll { $0.id == id }
        return items.count != before
    }

    /// Тухайн өдөр (local timezone) дээрх reminder-ууд — calendar-ийн цэгүүдэд.
    public func onDate(_ day: CalendarDay, in tz: TimeZone) -> [Reminder] {
        items.filter { CalendarDay($0.dueAt, in: tz) == day }.sorted { $0.dueAt < $1.dueAt }
    }

    /// Хуучин дууссан item-уудыг retention-оос хэтэрвэл устгана.
    @discardableResult
    public mutating func prune(now: Date, keepDone: TimeInterval) -> Int {
        let before = items.count
        items.removeAll { $0.done && now.timeIntervalSince($0.dueAt) > keepDone }
        return before - items.count
    }

    private func index(of id: UUID) throws -> Int {
        guard let i = items.firstIndex(where: { $0.id == id }) else { throw ReminderError.notFound(id) }
        return i
    }
}
