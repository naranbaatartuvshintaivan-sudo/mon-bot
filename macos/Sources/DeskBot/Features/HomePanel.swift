import SwiftUI
import DeskBotCore

/// C# HomePanel: том цаг + огноо, дараагийн reminder, now playing, CPU/RAM/Battery.
/// Уншиж чадаагүй утга → "—" + тайлбар (хуурамч тоо байхгүй).
struct HomePanel: View {
    let deps: ControlCenterDeps
    var openReminders: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 10) {
                Card(padding: 16) {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Fmt.time.string(from: ctx.date))
                                .font(.system(size: 44, weight: .light).monospacedDigit())
                                .foregroundStyle(CC.text)
                            Text(Fmt.longDate.string(from: ctx.date))
                                .font(.system(size: 12.5)).foregroundStyle(CC.secondary)
                        }
                    }
                }
                Button(action: openReminders) { nextReminder }.buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                nowPlaying
                HStack(spacing: 8) {
                    StatTile(title: "CPU", value: deps.system.cpuPercent.map { "\(Int($0.rounded()))%" },
                             missing: "measuring…")
                    StatTile(title: "RAM", value: deps.system.memory.map { "\(Int($0.percent.rounded()))%" },
                             missing: "unavailable")
                    StatTile(title: "Battery", value: batteryText, missing: batteryMissing,
                             tint: CompanionRules.isBatteryLow(deps.system.battery) ? CC.amber : CC.text)
                }
                if let m = deps.system.memory {
                    Caption(String(format: "RAM %.1f / %.0f GB used", m.usedGB, m.totalGB)).padding(.leading, 4)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var nextReminder: some View {
        let next = deps.reminders.book.nextUpcoming(now: .now)
        let pending = deps.reminders.book.hasFiredPending
        return Card {
            HStack(spacing: 10) {
                Image(systemName: "bell.fill")
                    .foregroundStyle(CC.amber)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10).fill(CC.amber.opacity(0.12)))
                VStack(alignment: .leading, spacing: 1) {
                    Caption(pending ? "Reminder due" : "Next reminder")
                    Text(next?.title ?? (pending ? "Open Reminders" : "Nothing scheduled"))
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(CC.text).lineLimit(1)
                    if let next { Caption(Fmt.dayTime.string(from: next.dueAt)) }
                }
                Spacer(minLength: 0)
            }
        }
        .contentShape(Rectangle())
    }

    /// Spotify / Apple Music. Байхгүй бол бодит шалтгаан (хуурамч дуу харуулахгүй).
    private var nowPlaying: some View {
        Card {
            if let n = deps.media.status.nowPlaying {
                HStack(spacing: 11) {
                    Artwork(image: deps.media.artwork, size: 46)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(n.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(CC.text).lineLimit(1)
                        Caption(n.artist.isEmpty ? n.player.displayName : n.artist).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Controls(media: deps.media, isPlaying: n.isPlaying, size: 26)
                }
            } else {
                MediaUnavailableView(status: deps.media.status)
            }
        }
    }

    private var batteryText: String? {
        let b = deps.system.battery
        guard b.present, let p = b.percent else { return nil }
        return "\(p)%"
    }

    private var batteryMissing: String {
        let b = deps.system.battery
        return b.present ? "unavailable" : "no battery"
    }
}

private struct StatTile: View {
    let title: String
    let value: String?
    let missing: String
    var tint: Color = CC.text

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Caption(title)
            Text(value ?? "—").font(.system(size: 20, weight: .semibold).monospacedDigit()).foregroundStyle(tint)
            if value == nil { Text(missing).font(.system(size: 9.5)).foregroundStyle(CC.muted) }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CC.card))
    }
}
