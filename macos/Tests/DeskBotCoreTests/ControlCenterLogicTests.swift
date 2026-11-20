import CoreGraphics
import Foundation
import Testing
@testable import DeskBotCore

@Suite struct HotkeyTests {
    @Test func parsesCommonForms() throws {
        let a = try HotkeySpec.parse("Option+Space")
        #expect(a.keyCode == 0x31)
        #expect(a.modifiers == [.option])
        #expect(a.modifiers.carbonMask == 0x800)
        #expect(a.symbols == "⌥Space")

        let b = try HotkeySpec.parse("ctrl + alt + space")
        #expect(b.modifiers == [.control, .option])
        #expect(b.description == "Ctrl+Option+Space")

        let c = try HotkeySpec.parse("⌘⇧K")
        #expect(c.keyCode == 0x28)
        #expect(c.modifiers == [.command, .shift])
        #expect(c.modifiers.carbonMask == 0x300)
        #expect(c.description == "Shift+Cmd+K")

        #expect(try HotkeySpec.parse("F5").keyCode == 0x60) // F-key modifier-гүй болно
    }

    @Test func rejectsBadInput() {
        #expect(throws: HotkeySpec.ParseError.empty) { try HotkeySpec.parse("  ") }
        #expect(throws: HotkeySpec.ParseError.needsModifier) { try HotkeySpec.parse("Space") }
        #expect(throws: HotkeySpec.ParseError.unknownModifier("Hyper")) { try HotkeySpec.parse("Hyper+K") }
        #expect(throws: HotkeySpec.ParseError.unknownKey("Ö")) { try HotkeySpec.parse("Cmd+Ö") }
    }

    @Test func descriptionRoundTrips() throws {
        for text in ["Option+Space", "Ctrl+Shift+F12", "Cmd+Option+7", "Ctrl+Esc"] {
            let spec = try HotkeySpec.parse(text)
            #expect(try HotkeySpec.parse(spec.description) == spec)
        }
    }
}

@Suite struct SettingsMigrationTests {
    @Test func v1DefaultHotkeyMigratesButCustomStays() throws {
        let v1 = try JSONDecoder().decode(AppSettings.self,
            from: Data(#"{"schemaVersion":1,"hotkey":"Ctrl+Alt+Space","theme":"Matrix"}"#.utf8))
        #expect(v1.hotkey == AppSettings.defaultHotkey)
        #expect(v1.schemaVersion == AppSettings.currentSchema)
        #expect(v1.theme == .matrix)
        #expect(v1.lastTab == "Home") // шинэ key — хуучин файлд байхгүй → default

        let custom = try JSONDecoder().decode(AppSettings.self,
            from: Data(#"{"schemaVersion":1,"hotkey":"Cmd+Shift+K"}"#.utf8))
        #expect(custom.hotkey == "Cmd+Shift+K")

        // v2 файлд Ctrl+Alt+Space гэж хэрэглэгч өөрөө тавьсан бол өөрчлөхгүй
        let v2 = try JSONDecoder().decode(AppSettings.self,
            from: Data(#"{"schemaVersion":2,"hotkey":"Ctrl+Alt+Space","lastTab":"Face"}"#.utf8))
        #expect(v2.hotkey == "Ctrl+Alt+Space")
        #expect(v2.lastTab == "Face")
    }

    @Test func invalidHotkeyFallsBackAndValidIsNormalized() {
        let s = AppSettings()
        s.hotkey = "banana"
        s.sanitize()
        #expect(s.hotkey == AppSettings.defaultHotkey)
        s.hotkey = "alt+space"
        s.sanitize()
        #expect(s.hotkey == "Option+Space")
    }
}

@Suite struct SystemMonitorMathTests {
    @Test func cpuUsageFromTickDelta() {
        let a = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let b = CPUTicks(user: 160, system: 70, idle: 1070, nice: 0) // +300 нийт, +220 idle
        #expect(abs(CPUTicks.usage(from: a, to: b)! - 26.666) < 0.01)
        #expect(CPUTicks.usage(from: b, to: a) == nil) // буцсан → мэдэгдэхгүй
        #expect(CPUTicks.usage(from: a, to: a) == nil)
    }

    @Test func memoryLikeActivityMonitor() {
        let m = MemoryUsage(internalPages: 300_000, purgeablePages: 20_000, wiredPages: 100_000,
                            compressedPages: 80_000, pageSize: 16_384, totalBytes: 16 * 1_073_741_824)
        #expect(m.usedBytes == 460_000 * 16_384)
        #expect(abs(m.usedGB - 7.019) < 0.01)
        #expect(abs(m.percent - 43.87) < 0.01)
        let clamped = MemoryUsage(internalPages: 10, purgeablePages: 20, wiredPages: 0, compressedPages: 0,
                                  pageSize: 1, totalBytes: 100)
        #expect(clamped.usedBytes == 0)
    }

    @Test func batteryPercentAndLowRule() {
        #expect(BatteryState.percent(current: 50, max: 100) == 50)
        #expect(BatteryState.percent(current: 4200, max: 5000) == 84)
        #expect(BatteryState.percent(current: 10, max: 0) == nil)
        #expect(CompanionRules.isBatteryLow(BatteryState(present: true, percent: 15, onAC: false, charging: false)))
        #expect(!CompanionRules.isBatteryLow(BatteryState(present: true, percent: 15, onAC: true, charging: true)))
        #expect(!CompanionRules.isBatteryLow(BatteryState(present: true, percent: 16, onAC: false, charging: false)))
        #expect(!CompanionRules.isBatteryLow(BatteryState(present: true, percent: nil, onAC: false, charging: false)))
        #expect(!CompanionRules.isBatteryLow(.none))
    }
}

@Suite struct FullscreenDetectorTests {
    // Үндсэн дэлгэц 1512×982, menu bar 32
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let me: Int32 = 42

    @Test func borderlessFullscreenGameDetected() {
        let game = WindowInfo(ownerPID: 7, layer: 0, bounds: screen)
        #expect(FullscreenDetector.isFullscreen(windows: [game], screenCG: screen, selfPID: me))
    }

    @Test func zoomedWindowOwnWindowsAndOverlaysIgnored() {
        let zoomed = WindowInfo(ownerPID: 7, layer: 0, bounds: CGRect(x: 0, y: 32, width: 1512, height: 950))
        let mine = WindowInfo(ownerPID: me, layer: 0, bounds: screen)
        let overlay = WindowInfo(ownerPID: 8, layer: 25, bounds: screen)   // status-level overlay
        let invisible = WindowInfo(ownerPID: 9, layer: 0, bounds: screen, alpha: 0)
        #expect(!FullscreenDetector.isFullscreen(windows: [zoomed, mine, overlay, invisible], screenCG: screen, selfPID: me))
    }

    @Test func secondaryScreenCoordinates() {
        // Үндсэн 1512×982; хоёр дахь дэлгэц баруун талд, Cocoa y=-200 (доош 200 шилжсэн), 1920×1080
        let cocoa = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
        let cg = FullscreenDetector.cgRect(ofCocoa: cocoa, primaryHeight: 982)
        #expect(cg == CGRect(x: 1512, y: 102, width: 1920, height: 1080))
        let game = WindowInfo(ownerPID: 7, layer: 0, bounds: cg)
        #expect(FullscreenDetector.isFullscreen(windows: [game], screenCG: cg, selfPID: me))
        #expect(!FullscreenDetector.isFullscreen(windows: [game], screenCG: screen, selfPID: me))
    }
}

@Suite struct ReminderUITests {
    let ub = TimeZone(identifier: "Asia/Ulaanbaatar")!

    @Test func calendarStartsMonday() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = ub
        // 2026-11-01 бол Ням → grid Даваа 10-р сарын 26-аас эхэлнэ
        let g = CalendarMonth.grid(year: 2026, month: 11, calendar: cal)
        #expect(g.count == 42)
        #expect(g.first == CalendarDay(year: 2026, month: 10, day: 26))
        #expect(g[6] == CalendarDay(year: 2026, month: 11, day: 1))
        #expect(g.last == CalendarDay(year: 2026, month: 12, day: 6))
        // 2027-02-01 Даваа → offset 0
        #expect(CalendarMonth.grid(year: 2027, month: 2, calendar: cal).first == CalendarDay(year: 2027, month: 2, day: 1))
    }

    @Test func monthShift() {
        #expect(CalendarMonth.shift(year: 2026, month: 12, by: 1) == (2027, 1))
        #expect(CalendarMonth.shift(year: 2026, month: 1, by: -1) == (2025, 12))
        #expect(CalendarMonth.shift(year: 2026, month: 5, by: 0) == (2026, 5))
    }

    @Test func parseTime() throws {
        let day = CalendarDay(year: 2026, month: 11, day: 20)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = ub
        for (text, h, m) in [("9:05", 9, 5), ("09:05", 9, 5), ("0905", 9, 5), ("21", 21, 0), ("7.30", 7, 30)] {
            let d = try #require(ReminderInput.parseTime(text, on: day, in: ub))
            let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: d)
            #expect(c == DateComponents(year: 2026, month: 11, day: 20, hour: h, minute: m))
        }
        for bad in ["24:00", "12:60", "ab", "", "1:2:3"] {
            #expect(ReminderInput.parseTime(bad, on: day, in: ub) == nil)
        }
    }
}
