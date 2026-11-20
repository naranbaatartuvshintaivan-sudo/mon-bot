import CoreGraphics
import Foundation
import Testing
@testable import DeskBotCore

private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

@Suite struct IslandModeMachineTests {
    /// Default: hoverDelay 120ms, autoCollapse 700ms.
    private func enter(_ m: inout IslandModeMachine, _ s: TimeInterval) {
        m.pointer(inside: true, now: at(s), hoverDelay: 0.12, autoCollapse: 0.7)
    }
    private func leave(_ m: inout IslandModeMachine, _ s: TimeInterval) {
        m.pointer(inside: false, now: at(s), hoverDelay: 0.12, autoCollapse: 0.7)
    }

    @Test func hoverAfterDelayAndCollapseAfterLeave() {
        var m = IslandModeMachine()
        enter(&m, 0)
        do { let r = m.tick(now: at(0.1), pinned: false); #expect(r == nil) }
        #expect(m.mode == .collapsed)
        do { let r = m.tick(now: at(0.13), pinned: false); #expect(r == .hover) }
        leave(&m, 1)
        do { let r = m.tick(now: at(1.6), pinned: false); #expect(r == nil) }
        do { let r = m.tick(now: at(1.71), pinned: false); #expect(r == .collapsed) }
    }

    @Test func quickPassDoesNotHover() {
        var m = IslandModeMachine()
        enter(&m, 0)
        leave(&m, 0.05)
        do { let r = m.tick(now: at(1), pinned: false); #expect(r == nil) }
        #expect(m.mode == .collapsed)
    }

    @Test func reenterCancelsCollapse() {
        var m = IslandModeMachine()
        m.set(.hover)
        enter(&m, 0)
        leave(&m, 1)
        enter(&m, 1.3)
        do { let r = m.tick(now: at(5), pinned: false); #expect(r == nil) }
        #expect(m.mode == .hover)
    }

    @Test func clickCycle() {
        var m = IslandModeMachine()
        do { let r = m.click(); #expect(r == .expanded) }
        do { let r = m.click(); #expect(r == .collapsed) }
        m.set(.hover)
        do { let r = m.click(); #expect(r == .expanded) }
        m.showAlert()
        do { let r = m.click(); #expect(r == .expanded) }
    }

    @Test func expandedUsesAtLeast900msAndRespectsPin() {
        var m = IslandModeMachine()
        enter(&m, 0)
        m.click()
        leave(&m, 1)
        do { let r = m.tick(now: at(1.8), pinned: false); #expect(r == nil) }       // 700ms биш, ≥900ms
        do { let r = m.tick(now: at(1.91), pinned: true); #expect(r == nil) }       // pin → хаагдахгүй
        #expect(m.mode == .expanded)

        enter(&m, 2); leave(&m, 3)
        do { let r = m.tick(now: at(4), pinned: false, textFocused: true); #expect(r == nil) }
        enter(&m, 4); leave(&m, 5)
        do { let r = m.tick(now: at(6), pinned: false); #expect(r == .collapsed) }
    }

    @Test func escapeIgnoresPinButOutsideClickDoesNot() {
        var m = IslandModeMachine()
        m.click()
        do { let r = m.outsideClick(pinned: true); #expect(r == nil) }
        #expect(m.mode == .expanded)
        do { let r = m.outsideClick(pinned: false); #expect(r == .collapsed) }
        m.click()
        do { let r = m.escape(); #expect(r == .collapsed) }
        do { let r = m.escape(); #expect(r == nil) } // collapsed үед юу ч хийхгүй
    }

    @Test func alertStaysUntilFinished() {
        var m = IslandModeMachine()
        m.showAlert()
        enter(&m, 0); leave(&m, 1)
        do { let r = m.tick(now: at(10), pinned: false); #expect(r == nil) }
        do { let r = m.outsideClick(pinned: false); #expect(r == nil) }
        #expect(m.mode == .alert)
        m.finishAlert()
        #expect(m.mode == .collapsed)

        m.showAlert()
        enter(&m, 11)
        m.finishAlert()
        #expect(m.mode == .hover) // cursor дээр нь байвал Hover
    }
}

@Suite struct IslandSizingTests {
    let s = IslandSizing()

    @Test func sizesMatchCSharp() {
        #expect(s.size(.collapsed) == CGSize(width: 190, height: 34))
        #expect(s.size(.hover) == CGSize(width: 360, height: 42))
        #expect(s.size(.alert) == CGSize(width: 400, height: 42 + 58))
        #expect(s.size(.expanded) == CGSize(width: 640, height: 420))
        #expect(s.faceWidth(.collapsed) == 114)
        #expect(s.faceWidth(.expanded) == 124)
    }

    @Test func notchWidensAndAddsInfoRow() {
        let notch = CGSize(width: 185, height: 38)
        #expect(s.size(.collapsed, notch: notch) == CGSize(width: 185 + 88, height: 38))
        #expect(s.headerHeight(.hover, notch: notch) == 42)
        #expect(s.size(.hover, notch: notch).height == 42 + IslandSizing.notchInfoRowHeight)
        #expect(s.size(.expanded, notch: notch) == CGSize(width: 640, height: 420))
    }

    @Test func expandedPlacementKeepsNotchCentered() throws {
        let mbp = ScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
            auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 663.5, height: 32),
            auxiliaryTopRight: CGRect(x: 848.5, y: 950, width: 663.5, height: 32))
        let notch = try #require(mbp.notchRect)
        let l = IslandLayout.place(screen: mbp, size: s.size(.expanded, notch: notch.size))
        let local = try #require(l.notchInIsland)
        #expect(abs(l.frame.midX - notch.midX) <= 0.5)
        #expect(l.frame.maxY == mbp.frame.maxY)
        #expect(abs(local.midX - l.frame.width / 2) <= 0.5)
        #expect(abs(try #require(l.earSpacing) - Double(l.frame.width / 2 + notch.width / 2)) <= 0.5)
    }

    @Test func expandedNeverWiderThanScreen() {
        let small = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 500, height: 400))
        let l = IslandLayout.place(screen: small, size: CGSize(width: 640, height: 420))
        #expect(l.frame.minX == 0)
        #expect(l.frame.width == 500)
    }
}

@Suite struct AutoHideTests {
    let island = CGRect(x: 1025, y: 1226, width: 190, height: 34) // дээд ирмэг 1260
    let far = CGPoint(x: 200, y: 400)

    @Test func hidesAfterDelayAndPeeksBackAtTopEdge() {
        var a = AutoHideTracker()
        a.update(now: at(0), enabled: true, mode: .collapsed, cursor: far, island: island)
        #expect(!a.isHidden)
        a.update(now: at(2.4), enabled: true, mode: .collapsed, cursor: far, island: island)
        #expect(!a.isHidden)
        do { let r = a.update(now: at(2.6), enabled: true, mode: .collapsed, cursor: far, island: island); #expect(r) }
        #expect(a.isHidden)

        // Нуугдсан island-ийн доорх (хуучин) хэсэг дээр cursor → гарахгүй
        a.update(now: at(3), enabled: true, mode: .collapsed, cursor: CGPoint(x: 1120, y: 1235), island: island)
        #expect(a.isHidden)
        // Дээд ирмэгт (хажуу тийш 40pt дотор) → гарна
        a.update(now: at(4), enabled: true, mode: .collapsed, cursor: CGPoint(x: 1240, y: 1259), island: island)
        #expect(!a.isHidden)
    }

    @Test func disabledOrNotCollapsedNeverHides() {
        var a = AutoHideTracker()
        a.update(now: at(0), enabled: false, mode: .collapsed, cursor: far, island: island)
        a.update(now: at(10), enabled: false, mode: .collapsed, cursor: far, island: island)
        #expect(!a.isHidden)
        a.update(now: at(20), enabled: true, mode: .expanded, cursor: far, island: island)
        a.update(now: at(30), enabled: true, mode: .expanded, cursor: far, island: island)
        #expect(!a.isHidden)
        // Expanded → Collapsed болсны дараа 2.5с тоолж эхэлнэ
        a.update(now: at(31), enabled: true, mode: .collapsed, cursor: far, island: island)
        #expect(!a.isHidden)
    }
}

@Suite struct IslandSnapTests {
    let imac = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 2240, height: 1260))

    @Test func snapsToCenterAndTop() {
        let r = IslandSnap.resolve(islandTopCenter: CGPoint(x: 1120 + 17, y: 1260 - 13), islandWidth: 190, screen: imac)
        #expect(r.offsetX == 0)
        #expect(r.topOffset == 0)
    }

    @Test func keepsFreePosition() {
        let r = IslandSnap.resolve(islandTopCenter: CGPoint(x: 1120 + 300.4, y: 1260 - 80), islandWidth: 190, screen: imac)
        #expect(r.offsetX == 300)
        #expect(r.topOffset == 80)
    }

    @Test func aboveScreenClampsToTop() {
        let r = IslandSnap.resolve(islandTopCenter: CGPoint(x: 500, y: 1300), islandWidth: 190, screen: imac)
        #expect(r.topOffset == 0)
    }

    @Test func topEdgeOverlappingNotchSnapsToNotch() {
        let mbp = ScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
            auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 663.5, height: 32),
            auxiliaryTopRight: CGRect(x: 848.5, y: 950, width: 663.5, height: 32))
        let r = IslandSnap.resolve(islandTopCenter: CGPoint(x: 756 + 120, y: 982), islandWidth: 273, screen: mbp)
        #expect(r.offsetX == 0)
        let farRight = IslandSnap.resolve(islandTopCenter: CGPoint(x: 756 + 400, y: 982), islandWidth: 190, screen: mbp)
        #expect(farRight.offsetX == 400)
    }

    @Test func secondaryScreenRelative() {
        let s = ScreenGeometry(frame: CGRect(x: -1920, y: 200, width: 1920, height: 1080))
        let r = IslandSnap.resolve(islandTopCenter: CGPoint(x: -960 - 250, y: 1280 - 40), islandWidth: 190, screen: s)
        #expect(r.offsetX == -250)
        #expect(r.topOffset == 40)
    }
}

@Suite struct IslandEasingTests {
    @Test func endpointsAndOvershoot() {
        #expect(IslandEasing.backOut(0) == 0)
        #expect(abs(IslandEasing.backOut(1) - 1) < 1e-12)
        #expect(IslandEasing.cubicOut(0) == 0)
        #expect(IslandEasing.cubicOut(1) == 1)
        let peak = stride(from: 0.0, through: 1, by: 0.01).map { IslandEasing.backOut($0) }.max()!
        #expect(peak > 1.0 && peak < 1.06) // BackEase 0.22 → бага зэрэг overshoot
        #expect(IslandEasing.cubicOut(0.5) == 0.875)
    }
}

@Suite struct DockScreenSettingTests {
    @Test func legacyMonitorIDIsMigrated() throws {
        let legacy = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"monitorID":"Studio Display#2"}"#.utf8))
        #expect(legacy.dockScreen == "Studio Display#2")
        let json = String(decoding: try JSONEncoder().encode(legacy), as: UTF8.self)
        #expect(json.contains("dockScreen"))
        #expect(!json.contains("monitorID"))
        let both = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"monitorID":"a","dockScreen":"b"}"#.utf8))
        #expect(both.dockScreen == "b")
    }
}
