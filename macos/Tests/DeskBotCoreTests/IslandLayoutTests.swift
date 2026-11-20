import CoreGraphics
import Testing
@testable import DeskBotCore

@Suite struct IslandLayoutTests {
    // iMac 24" (notch-гүй), 2240×1260 pt
    let imac = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 2240, height: 1260))

    // MacBook Pro 14" (notch 185pt, menu bar 32pt), 1512×982 pt
    let mbp = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaTop: 32,
        auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 663.5, height: 32),
        auxiliaryTopRight: CGRect(x: 848.5, y: 950, width: 663.5, height: 32))

    @Test func noNotchIsTopCenterPill() {
        #expect(imac.notchRect == nil)
        let l = IslandLayout.collapsed(screen: imac, width: 190, height: 34)
        #expect(!l.hasNotch)
        #expect(l.frame == CGRect(x: 1025, y: 1226, width: 190, height: 34))
        #expect(l.frame.maxY == imac.frame.maxY) // menu bar-ийн дээгүүр, дээд ирмэгт наалдсан
    }

    @Test func notchIsWrappedWithEars() throws {
        let notch = try #require(mbp.notchRect)
        #expect(notch.width == 185)
        let l = IslandLayout.collapsed(screen: mbp, width: 190, height: 34)
        let local = try #require(l.notchInIsland)
        #expect(l.frame.width >= 185 + 2 * IslandLayout.minEarWidth)
        #expect(abs(l.frame.midX - notch.midX) <= 0.5)
        #expect(l.frame.maxY == mbp.frame.maxY)
        // notch нь island-ийн дотор, дээд ирмэгт
        #expect(local.minX >= IslandLayout.minEarWidth - 0.5)
        #expect(local.maxY == l.frame.height)
    }

    @Test func movedIslandIgnoresNotch() {
        let l = IslandLayout.collapsed(screen: mbp, width: 190, height: 34, topOffset: 40)
        #expect(!l.hasNotch)
        #expect(l.frame.maxY == mbp.frame.maxY - 40)
    }

    @Test func offsetIsClampedToScreen() {
        let l = IslandLayout.collapsed(screen: imac, width: 190, height: 34, offsetX: 99_999)
        #expect(l.frame.maxX == imac.frame.maxX)
    }

    @Test func secondaryScreenOrigin() {
        let s = ScreenGeometry(frame: CGRect(x: -1920, y: 200, width: 1920, height: 1080))
        let l = IslandLayout.collapsed(screen: s, width: 190, height: 34)
        #expect(l.frame.midX == -960)
        #expect(l.frame.maxY == 1280)
    }
}
