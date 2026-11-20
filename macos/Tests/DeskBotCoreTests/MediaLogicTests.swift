import Foundation
import Testing
@testable import DeskBotCore

private let us = "\u{1F}"

@Suite struct MediaScriptOutputTests {
    @Test func parsesSpotifyWithMillisecondDurationAndArtwork() throws {
        let out = ["playing", "Song, Part 2", "Artist", "Album", "12,5", "215000", "https://i.scdn.co/image/abc"].joined(separator: us)
        guard case .track(let n) = MediaScriptOutput.parse(out, player: .spotify) else { Issue.record("no track"); return }
        #expect(n.title == "Song, Part 2")      // таслал нь талбар таслахгүй
        #expect(n.position == 12.5)             // locale-ийн таслалтай бутархай
        #expect(n.duration == 215)              // ms → s
        #expect(n.isPlaying)
        #expect(n.artworkURL?.host == "i.scdn.co")
        #expect(n.summary == "Song, Part 2 · Artist")
    }

    @Test func parsesMusicSecondsAndPaused() {
        let out = ["paused", "Track", "", "LP", "30", "180.5", ""].joined(separator: us)
        guard case .track(let n) = MediaScriptOutput.parse(out, player: .music) else { Issue.record("no track"); return }
        #expect(!n.isPlaying)
        #expect(n.duration == 180.5)
        #expect(n.artworkURL == nil)
        #expect(n.summary == "Track")
    }

    @Test func stoppedEmptyOrGarbageIsIdle() {
        #expect(MediaScriptOutput.parse("stopped", player: .music) == .idle)
        #expect(MediaScriptOutput.parse("", player: .spotify) == .idle)
        #expect(MediaScriptOutput.parse(["playing", "", "a", "b", "1", "2"].joined(separator: us), player: .music) == .idle)
        // http (https биш) artwork, сөрөг/буруу тоо → nil
        let out = ["playing", "T", "A", "B", "-3", "abc", "http://x/y.jpg"].joined(separator: us)
        guard case .track(let n) = MediaScriptOutput.parse(out, player: .spotify) else { Issue.record("no track"); return }
        #expect(n.position == nil && n.duration == nil && n.artworkURL == nil)
    }

    @Test func clockFormat() {
        #expect(MediaScriptOutput.clock(0) == "0:00")
        #expect(MediaScriptOutput.clock(65.9) == "1:05")
        #expect(MediaScriptOutput.clock(3725) == "1:02:05")
    }
}

@Suite struct MediaPolicyTests {
    let playingSpotify = NowPlaying(player: .spotify, title: "A", artist: "x", album: "", position: 10, duration: 100, isPlaying: true)
    let pausedMusic = NowPlaying(player: .music, title: "B", artist: "y", album: "", position: 5, duration: 50, isPlaying: false)

    @Test func onlyRunningPlayersAreQueried() {
        #expect(MediaPolicy.playersToQuery(running: [], lastActive: .music).isEmpty)
        #expect(MediaPolicy.playersToQuery(running: [.music], lastActive: .spotify) == [.music])
        #expect(MediaPolicy.playersToQuery(running: [.music, .spotify], lastActive: .music) == [.music, .spotify])
    }

    @Test func resolvePrefersPlayingThenLastActive() {
        #expect(MediaPolicy.resolve([:], lastActive: nil) == .noPlayer)
        #expect(MediaPolicy.resolve([.spotify: .track(playingSpotify), .music: .track(pausedMusic)], lastActive: .music)
                == .playing(playingSpotify))
        var pausedSpotify = playingSpotify
        pausedSpotify.isPlaying = false
        #expect(MediaPolicy.resolve([.spotify: .track(pausedSpotify), .music: .track(pausedMusic)], lastActive: .music)
                == .paused(pausedMusic))
        #expect(MediaPolicy.resolve([.music: .idle], lastActive: nil) == .nothingPlaying(.music))
        #expect(MediaPolicy.resolve([.music: .idle, .spotify: .permissionDenied], lastActive: nil) == .permissionNeeded(.spotify))
        #expect(MediaPolicy.resolve([.music: .failed("timeout")], lastActive: nil) == .error(.music, "timeout"))
    }

    @Test func errorCodesMap() {
        #expect(MediaPolicy.result(forError: -1743, message: "") == .permissionDenied)
        #expect(MediaPolicy.result(forError: -1744, message: "") == .permissionPending)
        #expect(MediaPolicy.result(forError: -1728, message: "") == .idle)
        #expect(MediaPolicy.result(forError: -1712, message: "AppleEvent timed out") == .failed("AppleEvent timed out (-1712)"))
    }

    @Test func pollingAndExpression() {
        #expect(MediaPolicy.pollInterval(.playing(playingSpotify)) == 1)
        #expect(MediaPolicy.pollInterval(.paused(pausedMusic)) == 5)
        #expect(MediaPolicy.pollInterval(.noPlayer) == 5)
        #expect(MediaPolicy.wantsMusicExpression(.playing(playingSpotify)))
        #expect(!MediaPolicy.wantsMusicExpression(.paused(pausedMusic)))
        #expect(!MediaPolicy.wantsMusicExpression(.permissionNeeded(.music)))
    }

    @Test func positionInterpolation() {
        #expect(playingSpotify.position(after: 3) == 13)
        #expect(playingSpotify.position(after: 500) == 100)   // duration-оор хязгаарлана
        #expect(pausedMusic.position(after: 30) == 5)          // pause үед хөдлөхгүй
        #expect(playingSpotify.progress(after: 0) == 0.1)
    }
}
