import AppKit
import Observation
import DeskBotCore

/// Spotify / Apple Music-ийн now playing + удирдлага (AppleScript). macOS-д нийтийн now-playing API байхгүй
/// тул бусад эх сурвалж (browser, YouTube) дэмжигдэхгүй — UI дээр шударгаар бичнэ.
///
/// Хамгаалалт:
/// - NSWorkspace-ээр ажиллаж байгаа player-ийг л асууна. Script бүр `if application id … is running`-ээр
///   эхэлдэг тул шалгалт ба илгээлтийн хооронд app хаагдсан ч AppleScript тэр app-ийг НЭЭХГҮЙ.
/// - Script-ийг тухайн app ажиллаж байх үед л compile хийнэ (суугаагүй app-ийн dictionary хайхгүй).
/// - Automation эрхийг урьдчилан хүсэхгүй — анхны Apple event дээр систем өөрөө асууна.
@MainActor
@Observable
final class MediaService {
    private(set) var status: MediaStatus = .noPlayer
    /// `status`-ийн position-ийг авсан агшин (progress-ийг interpolate хийнэ).
    private(set) var sampledAt = Date()
    private(set) var artwork: NSImage?

    @ObservationIgnored var onChange: ((MediaStatus) -> Void)?
    @ObservationIgnored private var lastActive: MediaPlayer?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var inFlight = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let runner = AppleScriptRunner()
    @ObservationIgnored private var artworkKey: String?

    func start() {
        guard observers.isEmpty else { return }
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                guard MediaPlayer.allCases.contains(where: { $0.bundleID == id }) else { return }
                MainActor.assumeIsolated { self?.poll() }
            })
        }
        poll()
    }

    /// Зөвхөн `--render-island` export-д (layout шалгах). App-д дуудагдахгүй.
    func setStatusForExport(_ s: MediaStatus) {
        status = s
        sampledAt = Date()
    }

    func stop() {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Controls

    func playPause() { send("playpause") }
    func next() { send("next track") }
    func previous() { send("previous track") }

    private func send(_ command: String) {
        guard let player = status.nowPlaying?.player ?? activePlayerForCommand(), isRunning(player) else { return }
        runner.command(command, player: player) { [weak self] in
            // Тоглуулагч төлөвөө шинэчлэх хугацаа өгөөд асууна.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.poll() }
        }
    }

    private func activePlayerForCommand() -> MediaPlayer? {
        switch status {
        case .nothingPlaying(let p): p
        default: nil
        }
    }

    // MARK: - Polling

    static func runningPlayers() -> Set<MediaPlayer> {
        let ids = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return Set(MediaPlayer.allCases.filter { ids.contains($0.bundleID) })
    }

    private func isRunning(_ p: MediaPlayer) -> Bool { Self.runningPlayers().contains(p) }

    func poll() {
        let players = MediaPolicy.playersToQuery(running: Self.runningPlayers(), lastActive: lastActive)
        guard !players.isEmpty else {
            apply([:])
            return
        }
        guard !inFlight else { return } // эрхийн цонх хүлээж байх үед давхар илгээхгүй
        inFlight = true
        runner.query(players) { [weak self] results in
            guard let self else { return }
            self.inFlight = false
            self.apply(results)
        }
    }

    private func apply(_ results: [MediaPlayer: PlayerQueryResult]) {
        let new = MediaPolicy.resolve(results, lastActive: lastActive)
        if let n = new.nowPlaying, n.isPlaying { lastActive = n.player }
        sampledAt = Date()
        let changed = new != status
        status = new
        updateArtwork(for: new.nowPlaying)
        if changed { onChange?(new) }
        schedule(MediaPolicy.pollInterval(new))
    }

    private func schedule(_ interval: TimeInterval) {
        if let t = timer, t.timeInterval == interval { return }
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: - Artwork

    /// Track солигдох үед л. Spotify: artwork url (Spotify CDN-ээс зураг татна — өөр юу ч илгээхгүй).
    /// Music: AppleScript-ийн raw data.
    private func updateArtwork(for n: NowPlaying?) {
        guard let n else {
            artwork = nil
            artworkKey = nil
            return
        }
        guard n.trackKey != artworkKey else { return }
        artworkKey = n.trackKey
        artwork = nil
        let key = n.trackKey
        switch n.player {
        case .spotify:
            guard let url = n.artworkURL else { return }
            Task { [weak self] in
                let session = URLSession(configuration: .ephemeral)
                guard let (data, _) = try? await session.data(from: url), let img = NSImage(data: data) else { return }
                await MainActor.run {
                    guard let self, self.artworkKey == key else { return }
                    self.artwork = img
                }
            }
        case .music:
            runner.musicArtwork { [weak self] data in
                guard let self, self.artworkKey == key, let data, let img = NSImage(data: data) else { return }
                self.artwork = img
            }
        }
    }
}

/// NSAppleScript-ийг нэг serial queue дээр (thread-safe биш, мөн дуудлага блоклодог — UI-г гацаахгүй).
/// Compile хийсэн script-ийг cache-лнэ.
private final class AppleScriptRunner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.deskbot.applescript", qos: .utility)
    private var cache: [String: NSAppleScript] = [:] // зөвхөн `queue` дээр

    /// Apple event-ийн хугацааны хязгаар (app гацсан үед queue удаан блоклогдохгүй).
    private static let timeout = 3

    private static func guarded(_ p: MediaPlayer, _ body: String) -> String {
        """
        if application id "\(p.bundleID)" is running then
            with timeout of \(timeout) seconds
                tell application id "\(p.bundleID)"
                    \(body)
                end tell
            end timeout
        end if
        return "not running"
        """
    }

    private static func nowPlayingScript(_ p: MediaPlayer) -> String {
        let art = p == .spotify ? "(artwork url of t)" : "\"\""
        return guarded(p, """
            if player state is stopped then return "stopped"
            set t to current track
            set sep to character id 31
            return (player state as text) & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & (player position as text) & sep & ((duration of t) as text) & sep & \(art)
            """)
    }

    private enum Outcome {
        case success(NSAppleEventDescriptor)
        case failure(PlayerQueryResult)
    }

    private func run(_ key: String, _ source: @autoclosure () -> String) -> Outcome {
        let script: NSAppleScript
        if let s = cache[key] {
            script = s
        } else {
            guard let s = NSAppleScript(source: source()) else { return .failure(PlayerQueryResult.failed("script")) }
            var err: NSDictionary?
            guard s.compileAndReturnError(&err) else {
                return .failure(PlayerQueryResult.failed((err?[NSAppleScript.errorMessage] as? String) ?? "compile failed"))
            }
            cache[key] = s
            script = s
        }
        var err: NSDictionary?
        let out = script.executeAndReturnError(&err)
        if let err {
            let code = (err[NSAppleScript.errorNumber] as? Int) ?? 0
            return .failure(MediaPolicy.result(forError: code, message: (err[NSAppleScript.errorMessage] as? String) ?? "error"))
        }
        return .success(out)
    }

    func query(_ players: [MediaPlayer], completion: @escaping @MainActor ([MediaPlayer: PlayerQueryResult]) -> Void) {
        queue.async { [self] in
            var results: [MediaPlayer: PlayerQueryResult] = [:]
            for p in players {
                switch run("np-\(p.rawValue)", Self.nowPlayingScript(p)) {
                case .success(let d):
                    let text = d.stringValue ?? ""
                    if text == "not running" { continue } // хооронд нь хаагдсан
                    results[p] = MediaScriptOutput.parse(text, player: p)
                case .failure(let r):
                    results[p] = r
                }
            }
            let snapshot = results
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(snapshot) } }
        }
    }

    func command(_ command: String, player: MediaPlayer, completion: @escaping @MainActor () -> Void) {
        queue.async { [self] in
            _ = run("cmd-\(player.rawValue)-\(command)", Self.guarded(player, command))
            DispatchQueue.main.async { MainActor.assumeIsolated { completion() } }
        }
    }

    func musicArtwork(completion: @escaping @MainActor (Data?) -> Void) {
        queue.async { [self] in
            let body = "return raw data of artwork 1 of current track"
            var data: Data?
            if case .success(let d) = run("art-music", Self.guarded(.music, body)), d.descriptorType != typeUnicodeText {
                data = d.data
            }
            let snapshot = data
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(snapshot) } }
        }
    }
}
