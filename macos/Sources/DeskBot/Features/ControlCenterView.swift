import SwiftUI
import DeskBotCore

/// Expanded island-ийн агуулга: tab strip (Home, Music, Reminders, Face, Settings) + pin/close.
/// Зөвхөн сонгосон tab л render хийгдэнэ (C# IFeaturePanel — харагдах үедээ л ажиллана).
struct ControlCenterView: View {
    let model: IslandModel
    let actions: IslandActions
    let deps: ControlCenterDeps

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(ControlTab.allCases) { tab in
                    let selected = model.selectedTab == tab
                    Button { select(tab) } label: {
                        Label(tab.rawValue, systemImage: tab.icon)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.white.opacity(selected ? 0.12 : 0)))
                            .foregroundStyle(selected ? .white : .white.opacity(0.6))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 8)
                CCIconButton(symbol: model.pinned ? "pin.fill" : "pin",
                             tint: model.pinned ? CC.accent : .white.opacity(0.7),
                             help: model.pinned ? "Unpin" : "Pin (stays open on outside click)",
                             action: actions.togglePin)
                CCIconButton(symbol: "xmark", tint: .white.opacity(0.7), help: "Close (Esc)", action: actions.close)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)

            content
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.selectedTab {
        case .home: HomePanel(deps: deps, openReminders: { select(.reminders) })
        case .music: MusicPanel(media: deps.media)
        case .reminders: RemindersPanel(deps: deps)
        case .face: FacePanel(deps: deps, visible: model.mode == .expanded)
        case .settings: SettingsPanel(deps: deps)
        }
    }

    private func select(_ tab: ControlTab) {
        model.selectedTab = tab
        deps.settings.lastTab = tab.rawValue
    }
}

struct CCIconButton: View {
    let symbol: String
    let tint: Color
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
