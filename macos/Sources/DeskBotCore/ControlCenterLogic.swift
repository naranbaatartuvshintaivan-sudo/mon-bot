import CoreGraphics
import Foundation

// M4 — control center, system monitor, hotkey, game mode-ийн цэвэр логик (AppKit/Carbon/IOKit-гүй, тест хийнэ).

// MARK: - Hotkey

/// Global hotkey ("Option+Space", "Ctrl+Alt+Space", "⌘⇧K" г.м.). Carbon `RegisterEventHotKey`-д
/// keyCode (kVK_*) ба modifier mask-ийг өгнө.
public struct HotkeySpec: Equatable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        /// Carbon: cmdKey 0x100, shiftKey 0x200, optionKey 0x800, controlKey 0x1000.
        public var carbonMask: UInt32 {
            var m: UInt32 = 0
            if contains(.command) { m |= 0x100 }
            if contains(.shift) { m |= 0x200 }
            if contains(.option) { m |= 0x800 }
            if contains(.control) { m |= 0x1000 }
            return m
        }
    }

    public var key: String          // "Space", "A", "5", "F1"
    public var keyCode: UInt32      // kVK_*
    public var modifiers: Modifiers

    public enum ParseError: Error, Equatable {
        case empty
        case unknownKey(String)
        case unknownModifier(String)
        /// F-key биш бол дор хаяж нэг modifier (эс бөгөөс энгийн бичихэд саад болно).
        case needsModifier
        /// Зөвхөн ⌥ / ⇧ + энгийн товч нь тэмдэгт бичдэг (⌥Space = nbsp, ⌥E = ´) — global болговол
        /// бүх app-д тэр тэмдэгтийг бичих боломжгүй болно. ⌃ эсвэл ⌘ нэмэх хэрэгтэй.
        case typesCharacter
    }

    /// macOS ANSI keyCode (Carbon Events.h kVK_*).
    static let keyCodes: [String: UInt32] = {
        var m: [String: UInt32] = [
            "A": 0x00, "S": 0x01, "D": 0x02, "F": 0x03, "H": 0x04, "G": 0x05, "Z": 0x06, "X": 0x07,
            "C": 0x08, "V": 0x09, "B": 0x0B, "Q": 0x0C, "W": 0x0D, "E": 0x0E, "R": 0x0F, "Y": 0x10,
            "T": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "9": 0x19,
            "7": 0x1A, "8": 0x1C, "0": 0x1D, "O": 0x1F, "U": 0x20, "I": 0x22, "P": 0x23, "L": 0x25,
            "J": 0x26, "K": 0x28, "N": 0x2D, "M": 0x2E,
            "SPACE": 0x31, "RETURN": 0x24, "TAB": 0x30, "ESCAPE": 0x35,
        ]
        let f: [UInt32] = [0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F]
        for (i, c) in f.enumerated() { m["F\(i + 1)"] = c }
        return m
    }()

    public static func parse(_ text: String) throws -> HotkeySpec {
        // "⌥Space" / "⌘⇧K" → тэмдэгтүүдийг "+"-ээр салгана
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for sym in ["⌃", "⌥", "⇧", "⌘"] { s = s.replacingOccurrences(of: sym, with: sym + "+") }
        let parts = s.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let last = parts.last else { throw ParseError.empty }

        var mods: Modifiers = []
        for p in parts.dropLast() {
            switch p.lowercased() {
            case "ctrl", "control", "⌃": mods.insert(.control)
            case "alt", "option", "opt", "⌥": mods.insert(.option)
            case "shift", "⇧": mods.insert(.shift)
            case "cmd", "command", "⌘": mods.insert(.command)
            default: throw ParseError.unknownModifier(p)
            }
        }
        let key = last.uppercased() == "ESC" ? "ESCAPE" : last.uppercased()
        guard let code = keyCodes[key] else { throw ParseError.unknownKey(last) }
        let isFKey = key.count >= 2 && key.hasPrefix("F") && Int(key.dropFirst()) != nil
        if mods.isEmpty && !isFKey { throw ParseError.needsModifier }
        let typingOnly = mods.isSubset(of: [.option, .shift])
        let nonTyping: Set<String> = ["ESCAPE", "TAB", "RETURN"]
        if typingOnly && !isFKey && !nonTyping.contains(key) { throw ParseError.typesCharacter }
        let display = key == "SPACE" ? "Space" : key == "RETURN" ? "Return" : key == "TAB" ? "Tab"
            : key == "ESCAPE" ? "Esc" : key
        return HotkeySpec(key: display, keyCode: code, modifiers: mods)
    }

    /// Хадгалах/харуулах хэлбэр: "Ctrl+Option+Shift+Cmd+Key" дараалал.
    public var description: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Ctrl") }
        if modifiers.contains(.option) { parts.append("Option") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.command) { parts.append("Cmd") }
        parts.append(key)
        return parts.joined(separator: "+")
    }

    /// Menu-д харуулах товч тэмдэглэгээ ("⌥Space").
    public var symbols: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + key
    }
}

// MARK: - System monitor

/// `host_statistics(HOST_CPU_LOAD_INFO)`-ийн tick-үүд (user, system, idle, nice).
public struct CPUTicks: Equatable, Sendable {
    public var user: UInt64, system: UInt64, idle: UInt64, nice: UInt64
    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }
    public var total: UInt64 { user &+ system &+ idle &+ nice }

    /// Хоёр дээжийн хоорондох ачаалал (0–100). Анхны дээж эсвэл counter буцсан бол nil.
    public static func usage(from a: CPUTicks, to b: CPUTicks) -> Double? {
        guard b.total > a.total, b.idle >= a.idle else { return nil }
        let dTotal = Double(b.total - a.total)
        let dIdle = Double(b.idle - a.idle)
        return min(max(100 * (dTotal - dIdle) / dTotal, 0), 100)
    }
}

/// `host_statistics64(HOST_VM_INFO64)` — Activity Monitor-ийн "Memory Used"-тэй ижил тооцоо:
/// app (internal − purgeable) + wired + compressed.
public struct MemoryUsage: Equatable, Sendable {
    public var usedBytes: UInt64
    public var totalBytes: UInt64

    public init(usedBytes: UInt64, totalBytes: UInt64) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
    }

    public init(internalPages: UInt64, purgeablePages: UInt64, wiredPages: UInt64, compressedPages: UInt64,
                pageSize: UInt64, totalBytes: UInt64) {
        let app = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        let used = (app + wiredPages + compressedPages) * pageSize
        self.init(usedBytes: min(used, totalBytes), totalBytes: totalBytes)
    }

    public var percent: Double { totalBytes == 0 ? 0 : 100 * Double(usedBytes) / Double(totalBytes) }
    public var usedGB: Double { Double(usedBytes) / 1_073_741_824 }
    public var totalGB: Double { Double(totalBytes) / 1_073_741_824 }
}

/// Battery (IOKit power source). Desktop Mac-д `present == false` → UI "No battery".
public struct BatteryState: Equatable, Sendable {
    public var present: Bool
    public var percent: Int?
    public var onAC: Bool
    public var charging: Bool

    public init(present: Bool, percent: Int?, onAC: Bool, charging: Bool) {
        self.present = present
        self.percent = percent
        self.onAC = onAC
        self.charging = charging
    }

    public static let none = BatteryState(present: false, percent: nil, onAC: true, charging: false)

    /// current/max capacity → %. max ≤ 0 бол мэдэгдэхгүй (nil) — хуурамч утга гаргахгүй.
    public static func percent(current: Int, max: Int) -> Int? {
        guard max > 0, current >= 0 else { return nil }
        return Swift.min(100, Int((Double(current) * 100 / Double(max)).rounded()))
    }
}

public enum CompanionRules {
    /// C#: HasBattery && !OnAcPower && 0 ≤ % ≤ 15.
    public static let lowBatteryPercent = 15

    public static func isBatteryLow(_ b: BatteryState) -> Bool {
        guard b.present, !b.onAC, let p = b.percent else { return false }
        return p >= 0 && p <= lowBatteryPercent
    }
}

// MARK: - Game mode

/// `CGWindowListCopyWindowInfo`-ийн нэг мөр (Screen Recording эрхгүйгээр авах талбарууд л).
public struct WindowInfo: Equatable, Sendable {
    public var ownerPID: Int32
    public var layer: Int
    /// CG global координат (origin үндсэн дэлгэцийн дээд зүүн, y доошоо).
    public var bounds: CGRect
    public var alpha: Double

    public init(ownerPID: Int32, layer: Int, bounds: CGRect, alpha: Double = 1) {
        self.ownerPID = ownerPID
        self.layer = layer
        self.bounds = bounds
        self.alpha = alpha
    }
}

public enum FullscreenDetector {
    /// Өөр app-ийн энгийн (layer 0), харагдах цонх дэлгэцийг бүтэн (menu bar-ийг оруулаад) хучиж байвал fullscreen.
    /// Zoom/maximize хийсэн цонх menu bar-ийн доороос эхэлдэг тул тооцогдохгүй.
    /// Native fullscreen Space-д island угаасаа харагдахгүй (`.fullScreenAuxiliary`-гүй).
    /// - screenCG: дэлгэцийн frame CG координатаар (`cgRect(ofCocoa:primaryHeight:)`).
    public static func isFullscreen(windows: [WindowInfo], screenCG: CGRect, selfPID: Int32) -> Bool {
        windows.contains { w in
            w.ownerPID != selfPID && w.layer == 0 && w.alpha > 0.01
                && w.bounds.insetBy(dx: -1, dy: -1).contains(screenCG)
        }
    }

    /// Cocoa (origin доод зүүн, y дээшээ) → CG global (origin үндсэн дэлгэцийн дээд зүүн, y доошоо).
    public static func cgRect(ofCocoa r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}

// MARK: - Reminders UI

public enum CalendarMonth {
    /// Даваа гарагаас эхэлсэн 6×7 = 42 өдөр (C# RenderCalendar).
    public static func grid(year: Int, month: Int, calendar: Calendar) -> [CalendarDay] {
        var cal = calendar
        cal.firstWeekday = 2
        guard let first = cal.date(from: DateComponents(year: year, month: month, day: 1)) else { return [] }
        let weekday = cal.component(.weekday, from: first)        // 1 = Ням
        let offset = (weekday + 5) % 7                            // Даваа = 0
        guard let start = cal.date(byAdding: .day, value: -offset, to: first) else { return [] }
        return (0..<42).compactMap { i in
            cal.date(byAdding: .day, value: i, to: start).map { CalendarDay($0, in: cal.timeZone) }
        }
    }

    public static func shift(year: Int, month: Int, by delta: Int) -> (year: Int, month: Int) {
        let m = (year * 12 + (month - 1)) + delta
        return (m / 12, m % 12 + 1)
    }
}

public enum ReminderInput {
    /// "9:05", "09:05", "0905" → тухайн өдрийн local цаг. Буруу бол nil.
    public static func parseTime(_ text: String, on day: CalendarDay, in tz: TimeZone) -> Date? {
        let t = text.trimmingCharacters(in: .whitespaces)
        var h: Int?, m: Int?
        if let c = t.firstIndex(where: { $0 == ":" || $0 == "." }) {
            h = Int(t[..<c]); m = Int(t[t.index(after: c)...])
        } else if t.count == 4, let v = Int(t) {
            h = v / 100; m = v % 100
        } else if t.count <= 2, let v = Int(t) {
            h = v; m = 0
        }
        guard let h, let m, (0...23).contains(h), (0...59).contains(m) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: h, minute: m))
    }
}
