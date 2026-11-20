import Foundation

// M5 — Music. macOS-д нийтийн now-playing API байхгүй (MediaRemote private, 15.4+-д 3rd-party-д хаагдсан).
// Тиймээс зөвхөн Spotify ба Apple Music-ийг AppleScript-ээр. Энд AppleScript-гүй цэвэр логик (тест хийнэ).

public enum MediaPlayer: String, CaseIterable, Codable, Sendable {
    case spotify = "Spotify"
    case music = "Music"

    public var bundleID: String {
        switch self {
        case .spotify: "com.spotify.client"
        case .music: "com.apple.Music"
        }
    }

    public var displayName: String { self == .music ? "Apple Music" : "Spotify" }

    /// AppleScript-ийн `duration` нэгж: Spotify — миллисекунд, Music — секунд.
    var durationScale: Double { self == .spotify ? 0.001 : 1 }
}

public struct NowPlaying: Equatable, Sendable {
    public var player: MediaPlayer
    public var title: String
    public var artist: String
    public var album: String
    /// Секунд. Дээж авсан агшинд.
    public var position: Double?
    public var duration: Double?
    public var isPlaying: Bool
    /// Spotify: https artwork url. Music: nil (artwork-ийг тусад нь raw data-аар авна).
    public var artworkURL: URL?

    public init(player: MediaPlayer, title: String, artist: String, album: String, position: Double?,
                duration: Double?, isPlaying: Bool, artworkURL: URL? = nil) {
        self.player = player
        self.title = title
        self.artist = artist
        self.album = album
        self.position = position
        self.duration = duration
        self.isPlaying = isPlaying
        self.artworkURL = artworkURL
    }

    /// Track солигдсон эсэхийг (artwork дахин татах) тодорхойлох түлхүүр.
    public var trackKey: String { "\(player.rawValue)|\(title)|\(artist)|\(album)" }

    /// "Title · Artist" (artist хоосон бол title л).
    public var summary: String { artist.isEmpty ? title : "\(title) · \(artist)" }

    /// Дээжээс хойш `elapsed` секунд өнгөрсөн байрлал (тоглож байвал), duration-оор хязгаарлана.
    public func position(after elapsed: TimeInterval) -> Double? {
        guard let p = position else { return nil }
        let v = isPlaying ? p + max(0, elapsed) : p
        if let d = duration, d > 0 { return min(v, d) }
        return v
    }

    /// 0…1 progress.
    public func progress(after elapsed: TimeInterval) -> Double? {
        guard let d = duration, d > 0, let p = position(after: elapsed) else { return nil }
        return min(max(p / d, 0), 1)
    }
}

/// Нэг player-ийг асуусны үр дүн.
public enum PlayerQueryResult: Equatable, Sendable {
    case track(NowPlaying)
    /// Ажиллаж байгаа ч юу ч тоглоогүй (stopped / track байхгүй).
    case idle
    /// Automation эрх өгөөгүй (-1743).
    case permissionDenied
    /// Эрхийн цонх гарч, хэрэглэгч хариулаагүй байна (-1744).
    case permissionPending
    /// Хариу ирээгүй (timeout г.м.) — өмнөх төлөвөө хадгална.
    case failed(String)
}

/// UI-д харуулах нийт төлөв. Хуурамч өгөгдөл байхгүй: мэдэхгүй бол тодорхой шалтгаантай.
public enum MediaStatus: Equatable, Sendable {
    /// Spotify / Apple Music аль нь ч ажиллаагүй (AppleScript илгээхгүй).
    case noPlayer
    case nothingPlaying(MediaPlayer)
    case permissionNeeded(MediaPlayer)
    case playing(NowPlaying)
    case paused(NowPlaying)
    case error(MediaPlayer, String)

    public var nowPlaying: NowPlaying? {
        switch self {
        case .playing(let n), .paused(let n): n
        default: nil
        }
    }

    public var isPlaying: Bool { if case .playing = self { true } else { false } }
}

public enum MediaPolicy {
    public static let playingInterval: TimeInterval = 1
    public static let idleInterval: TimeInterval = 5
    /// errAEEventNotPermitted, errAEEventWouldRequireUserConsent, procNotFound, errAENoSuchObject
    public static let notPermitted = -1743
    public static let wouldRequireConsent = -1744
    public static let processNotFound = -600
    public static let noSuchObject = -1728

    /// Тоглож байхад 1с (progress, track солигдох), бусад үед 5с.
    public static func pollInterval(_ status: MediaStatus) -> TimeInterval {
        status.isPlaying ? playingInterval : idleInterval
    }

    /// Зөвхөн АЖИЛЛАЖ БАЙГАА player-уудыг асууна (ажиллаагүй app руу Apple event илгээвэл тэр app нээгдэнэ).
    /// Сүүлд тоглуулсан player-ийг эхэнд.
    public static func playersToQuery(running: Set<MediaPlayer>, lastActive: MediaPlayer?) -> [MediaPlayer] {
        MediaPlayer.allCases.filter { running.contains($0) }
            .sorted { a, b in (a == lastActive ? 0 : 1) < (b == lastActive ? 0 : 1) }
    }

    /// Player бүрийн үр дүнгээс нэг төлөв сонгоно: тоглож буй > сүүлд идэвхтэй байсны pause >
    /// бусад pause > эрх хэрэгтэй > юу ч тоглоогүй > алдаа.
    public static func resolve(_ results: [MediaPlayer: PlayerQueryResult], lastActive: MediaPlayer?) -> MediaStatus {
        if results.isEmpty { return .noPlayer }
        let order = MediaPlayer.allCases.sorted { a, b in (a == lastActive ? 0 : 1) < (b == lastActive ? 0 : 1) }
        var tracks: [NowPlaying] = []
        for p in order { if case .track(let n)? = results[p] { tracks.append(n) } }
        if let n = tracks.first(where: \.isPlaying) { return .playing(n) }
        if let n = tracks.first { return .paused(n) }
        for p in order {
            switch results[p] {
            case .permissionDenied?, .permissionPending?: return .permissionNeeded(p)
            default: continue
            }
        }
        for p in order { if case .idle? = results[p] { return .nothingPlaying(p) } }
        for p in order { if case .failed(let m)? = results[p] { return .error(p, m) } }
        return .noPlayer
    }

    /// AppleScript-ийн алдааны код → үр дүн.
    public static func result(forError code: Int, message: String) -> PlayerQueryResult {
        switch code {
        case notPermitted: .permissionDenied
        case wouldRequireConsent: .permissionPending
        case noSuchObject: .idle
        default: .failed("\(message) (\(code))")
        }
    }

    /// Music expression layer (priority 20) идэвхтэй байх эсэх.
    public static func wantsMusicExpression(_ status: MediaStatus) -> Bool { status.isPlaying }
}

/// AppleScript-ийн буцаасан мөрийг задлана. Формат: талбаруудыг U+001F (unit separator)-ээр:
/// `state␟title␟artist␟album␟position␟duration␟artworkURL` эсвэл зүгээр "stopped" / "not running".
public enum MediaScriptOutput {
    public static let separator: Character = "\u{1F}"

    public static func parse(_ text: String, player: MediaPlayer) -> PlayerQueryResult {
        let fields = text.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
        let state = fields.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard fields.count >= 6, state == "playing" || state == "paused" else { return .idle }
        let title = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return .idle }
        let duration = number(fields[5]).map { $0 * player.durationScale }
        let art = fields.count > 6 ? URL(string: fields[6].trimmingCharacters(in: .whitespaces)) : nil
        return .track(NowPlaying(player: player, title: title, artist: fields[2], album: fields[3],
                                 position: number(fields[4]), duration: duration.flatMap { $0 > 0 ? $0 : nil },
                                 isPlaying: state == "playing",
                                 artworkURL: art.flatMap { $0.scheme == "https" ? $0 : nil }))
    }

    /// AppleScript-ийн `as text` нь locale-оос хамаарч "12,5" гэж бичиж болно.
    static func number(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let v = Double(t), v.isFinite, v >= 0 else { return nil }
        return v
    }

    /// m:ss эсвэл h:mm:ss.
    public static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}
