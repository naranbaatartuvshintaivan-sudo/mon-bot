import AppKit
import SwiftUI
import DeskBotCore

/// Music tab: artwork, title/artist/album, progress, prev/play/next. Хуурамч өгөгдөл байхгүй —
/// тоглуулагч байхгүй, эрх өгөөгүй, юу ч тоглоогүй үед бодит шалтгаан ба заавар.
struct MusicPanel: View {
    let media: MediaService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch media.status {
            case .playing(let n), .paused(let n):
                track(n)
            default:
                MediaUnavailableView(status: media.status, large: true)
            }
            Spacer(minLength: 0)
            Caption("Only Spotify and Apple Music are supported. macOS has no public now-playing API, so browser audio (Chrome, Safari, YouTube) can’t be shown.")
        }
    }

    private func track(_ n: NowPlaying) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Artwork(image: media.artwork, size: 132)
            VStack(alignment: .leading, spacing: 4) {
                Text(n.title).font(.system(size: 18, weight: .semibold)).foregroundStyle(CC.text).lineLimit(2)
                if !n.artist.isEmpty { Text(n.artist).font(.system(size: 13)).foregroundStyle(CC.secondary).lineLimit(1) }
                if !n.album.isEmpty { Text(n.album).font(.system(size: 12)).foregroundStyle(CC.muted).lineLimit(1) }
                Text("via \(n.player.displayName)").font(.system(size: 10.5, weight: .medium)).foregroundStyle(CC.accent)
                    .padding(.top, 2)
                Spacer(minLength: 8)
                ProgressRow(media: media, nowPlaying: n)
                Controls(media: media, isPlaying: n.isPlaying, size: 34).padding(.top, 4)
            }
            .frame(maxHeight: 180)
        }
    }
}

/// Тоглуулагч байхгүй / эрх хэрэгтэй / юу ч тоглоогүй / алдаа — бодит заавартай.
struct MediaUnavailableView: View {
    let status: MediaStatus
    var large = false

    static let automationSettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: large ? 26 : 16, weight: .light))
                .foregroundStyle(tint)
                .frame(width: large ? 64 : 46, height: large ? 64 : 46)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: large ? 15 : 13, weight: .semibold)).foregroundStyle(CC.text)
                Caption(detail)
                if case .permissionNeeded = status {
                    SmallButton("Open Automation settings") { NSWorkspace.shared.open(Self.automationSettings) }
                        .padding(.top, 3)
                }
            }
        }
    }

    private var icon: String {
        switch status {
        case .permissionNeeded: "lock"
        case .error: "exclamationmark.triangle"
        default: "music.note"
        }
    }

    private var tint: Color {
        switch status {
        case .permissionNeeded: CC.amber
        case .error: CC.danger
        default: CC.muted
        }
    }

    private var title: String {
        switch status {
        case .noPlayer: "Nothing playing"
        case .nothingPlaying(let p): "\(p.displayName) is open"
        case .permissionNeeded(let p): "Permission needed for \(p.displayName)"
        case .error(let p, _): "Couldn’t read \(p.displayName)"
        case .playing(let n), .paused(let n): n.title
        }
    }

    private var detail: String {
        switch status {
        case .noPlayer: "Open Spotify or Apple Music and play something."
        case .nothingPlaying: "Nothing is playing right now."
        case .permissionNeeded(let p):
            "Allow in System Settings → Privacy & Security → Automation → DeskBot → \(p.displayName)."
        case .error(_, let m): m
        case .playing(let n), .paused(let n): n.artist
        }
    }
}

struct Artwork: View {
    let image: NSImage?
    let size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous).fill(Color.white.opacity(0.08))
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note").font(.system(size: size * 0.3, weight: .light)).foregroundStyle(CC.muted)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.12, style: .continuous))
    }
}

/// Progress — тоглож байхад 0.5с тутам interpolate хийнэ (AppleScript-ийг 1с тутам асуудаг).
struct ProgressRow: View {
    let media: MediaService
    let nowPlaying: NowPlaying

    var body: some View {
        TimelineView(.periodic(from: .now, by: nowPlaying.isPlaying ? 0.5 : 60)) { ctx in
            let elapsed = ctx.date.timeIntervalSince(media.sampledAt)
            VStack(spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(CC.accent)
                            .frame(width: geo.size.width * (nowPlaying.progress(after: elapsed) ?? 0))
                    }
                }
                .frame(height: 4)
                HStack {
                    Text(nowPlaying.position(after: elapsed).map(MediaScriptOutput.clock) ?? "—:—")
                    Spacer()
                    Text(nowPlaying.duration.map(MediaScriptOutput.clock) ?? "—:—")
                }
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(CC.secondary)
            }
        }
    }
}

struct Controls: View {
    let media: MediaService
    let isPlaying: Bool
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: 10) {
            button("backward.fill", size * 0.8, "Previous", media.previous)
            button(isPlaying ? "pause.fill" : "play.fill", size, isPlaying ? "Pause" : "Play", media.playPause)
            button("forward.fill", size * 0.8, "Next", media.next)
        }
    }

    private func button(_ symbol: String, _ s: CGFloat, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: s * 0.42, weight: .semibold))
                .foregroundStyle(CC.text)
                .frame(width: s, height: s)
                .background(Circle().fill(Color.white.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Hover mode-ийн жижиг мөр: тоглож байвал "♪ Title · Artist", эс бөгөөс nil (цаг харуулна).
struct HoverNowPlaying: View {
    let nowPlaying: NowPlaying
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "music.note").font(.system(size: 10, weight: .semibold)).foregroundStyle(CC.accent)
            Text(nowPlaying.summary)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
