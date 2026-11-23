import Foundation
import Testing
@testable import DeskBotCore

@Suite struct ActivityLogicTests {
    @Test func clipboardSkipsPasswordManagers() {
        #expect(ClipboardPolicy.shouldReact(types: ["public.utf8-plain-text"]))
        #expect(!ClipboardPolicy.shouldReact(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        #expect(!ClipboardPolicy.shouldReact(types: ["org.nspasteboard.TransientType"]))
        #expect(!ClipboardPolicy.shouldReact(types: []))   // clearContents only
    }

    @Test func throttle() {
        var t = ReactionThrottle(minInterval: 1)
        let t0 = Date(timeIntervalSince1970: 0)
        let a = t.allow(now: t0)
        let b = t.allow(now: t0.addingTimeInterval(0.5))
        let c = t.allow(now: t0.addingTimeInterval(1.1))
        #expect(a && !b && c)
    }

    @Test func downloadExtensions() {
        #expect(DownloadFiles.isInProgress("Unconfirmed 812.crdownload"))
        #expect(DownloadFiles.isInProgress("Xcode.xip.download"))
        #expect(DownloadFiles.isInProgress("movie.mp4.PART"))
        #expect(!DownloadFiles.isInProgress("report.pdf"))
        #expect(!DownloadFiles.isInProgress(".hidden.part"))
        #expect(DownloadFiles.anyInProgress(["a.zip", "b.dmg.crdownload"]))
        #expect(!DownloadFiles.anyInProgress(["a.zip", ".DS_Store"]))
    }

    @Test func pendingLaunches() {
        var p = PendingLaunches()
        let t0 = Date(timeIntervalSince1970: 0)
        p.begin(pid: 1, now: t0)
        p.begin(pid: 2, now: t0.addingTimeInterval(5))
        p.end(pid: 1)
        #expect(!p.isEmpty)
        let early = p.prune(now: t0.addingTimeInterval(10))    // pid 2 5с л болсон
        let late = p.prune(now: t0.addingTimeInterval(13.5))   // timeout
        #expect(!early && late)
    }

    @Test func copiedExpression() {
        #expect(RobotExpression(rawValue: "Copied") == .copied)
        #expect(!ExpressionRules.canBeBaseMood(.copied))
        #expect(FaceLibrary.parameters(for: .copied).overlay == .check)
        #expect(ExpressionSource.userAction.priority > ExpressionSource.activeTask.priority)
        #expect(ExpressionSource.userAction.priority < ExpressionSource.userClick.priority)
    }

    @Test func reactionSettingsDefaultsAndRoundtrip() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"theme":"Aurora"}"#.utf8))
        #expect(old.reactToCopy && old.reactToAppLaunch && !old.reactToDownloads)
        old.reactToDownloads = true
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(old))
        #expect(back.reactToDownloads)
    }
}
