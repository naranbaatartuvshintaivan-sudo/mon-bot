import SwiftUI
import DeskBotCore

/// Dynamic Island. Panel нь island + pad; island нь panel-ийн дээд төвд.
/// - Notch-гүй: robot нүүр header-ийн төвд, Hover/Expanded үед зүүн талд цаг.
/// - Notch-тэй: нүд нь notch-ийн хоёр талын "чих"-нд; Hover-ийн цаг notch-ийн доорх мөрөнд.
struct IslandView: View {
    static let faceMarginY: CGFloat = 1
    static let accent = Color(red: 0x33 / 255, green: 0xE1 / 255, blue: 1)

    let model: IslandModel
    let face: FaceDriver
    let actions: IslandActions
    let deps: ControlCenterDeps

    var body: some View {
        island
            .frame(width: model.islandSize.width, height: model.islandSize.height)
            .offset(y: model.hiddenUp ? -(model.islandSize.height - AutoHideTracker.peek) : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var shape: UnevenRoundedRectangle {
        let r = min(model.cornerRadius, model.islandSize.height / 2)
        let top = model.attachedTop ? 0 : r
        return UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: r,
                                      bottomTrailingRadius: r, topTrailingRadius: top, style: .continuous)
    }

    private var fill: Color {
        model.background == .translucent
            ? Color(red: 0x12 / 255, green: 0x16 / 255, blue: 0x1E / 255).opacity(model.backgroundOpacity * 0.78)
            : Color(red: 0x05 / 255, green: 0x06 / 255, blue: 0x08 / 255).opacity(model.backgroundOpacity)
    }

    private var island: some View {
        ZStack(alignment: .top) {
            shape.fill(fill)
            shape.strokeBorder(Color.white.opacity(model.mode == .collapsed ? 0.04 : 0.08), lineWidth: 1)

            if model.simulatedNotch, let n = model.notchSize {
                Rectangle().fill(Color(white: 0.3)).frame(width: n.width, height: n.height)
            }

            VStack(spacing: 0) {
                header.frame(height: model.headerHeight)
                if model.mode == .hover, model.notchSize != nil {
                    HStack { hoverInfo; Spacer() }
                        .padding(.horizontal, 16)
                        .frame(height: IslandSizing.notchInfoRowHeight)
                        .transition(.opacity)
                }
                if model.mode == .alert {
                    AlertBar(title: model.alertTitle, time: model.alertTime, finish: actions.finishAlert)
                        .transition(.opacity)
                }
                if model.mode == .expanded {
                    ControlCenterView(model: model, actions: actions, deps: deps)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
            }
        }
        .clipShape(shape)
        .contentShape(shape)
        .environment(\.colorScheme, .dark)
    }

    /// Hover: тоглож байвал "♪ Title · Artist", эс бөгөөс цаг.
    @ViewBuilder
    private var hoverInfo: some View {
        if let n = deps.media.status.nowPlaying, n.isPlaying {
            HoverNowPlaying(nowPlaying: n)
        } else {
            ClockLabel()
        }
    }

    @ViewBuilder
    private var header: some View {
        let faceH = max(0, model.headerHeight - 2 * Self.faceMarginY)
        if let n = model.notchSize {
            FaceSlot(driver: face, notchWidth: Double(n.width), paused: model.facePaused)
                .frame(height: faceH)
        } else {
            ZStack {
                if model.mode != .collapsed {
                    // Hover: тоглож байвал дуу (face-ийн зүүн талд багтаана), Expanded / Alert: цаг.
                    HStack { (model.mode == .hover ? AnyView(hoverInfo) : AnyView(ClockLabel())); Spacer(minLength: 0) }
                        .padding(.leading, 16)
                        .frame(width: max(0, (model.islandSize.width - model.faceWidth) / 2 - 4), alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }
                FaceSlot(driver: face, notchWidth: nil, paused: model.facePaused)
                    .frame(width: model.faceWidth, height: faceH)
            }
        }
    }
}

/// Debug export (ImageRenderer): NSView-ийн оронд face-ийг bitmap болгон зурна.
/// (`@Entry` macro нь Command Line Tools-д plugin-гүй тул гараар.)
private struct FaceAsImageKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var faceAsImage: Bool {
        get { self[FaceAsImageKey.self] }
        set { self[FaceAsImageKey.self] = newValue }
    }
}

/// Robot face — app дотор NSView (CPU хэмнэлттэй), export үед bitmap.
struct FaceSlot: View {
    let driver: FaceDriver
    let notchWidth: Double?
    let paused: Bool
    @Environment(\.faceAsImage) private var asImage

    var body: some View {
        if asImage {
            GeometryReader { geo in
                let spacing = notchWidth.map { Double(geo.size.width) / 2 + $0 / 2 }
                if let img = FaceRenderer.image(size: geo.size, scale: 2, snapshot: driver.snapshot,
                                                style: driver.style(spacingOverride: spacing)) {
                    Image(decorative: img, scale: 2)
                }
            }
        } else {
            RobotFaceView(driver: driver, notchWidth: notchWidth, paused: paused)
        }
    }
}

/// Цаг + огноо. Зөвхөн харагдах үедээ (Hover/Expanded) секунд тутам шинэчлэгдэнэ.
private struct ClockLabel: View {
    private static let time: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
    private static let date: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE d"; return f }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Self.time.string(from: ctx.date))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                Text(Self.date.string(from: ctx.date))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }
}

/// Reminder alert (C# AlertBar). M4-д ReminderService-ийн Snooze/Done-той холбогдоно.
private struct AlertBar: View {
    let title: String
    let time: String
    let finish: (_ snoozed: Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.fill").foregroundStyle(IslandView.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(time).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 8)
            Button("Snooze 5m") { finish(true) }.buttonStyle(PillButtonStyle(prominent: false))
            Button("Done") { finish(false) }.buttonStyle(PillButtonStyle(prominent: true))
        }
        .padding(.horizontal, 16)
        .frame(height: IslandSizing.alertBarHeight)
    }
}

private struct PillButtonStyle: ButtonStyle {
    let prominent: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(prominent ? IslandView.accent : Color.white.opacity(0.12)))
            .foregroundStyle(prominent ? Color.black : Color.white)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
