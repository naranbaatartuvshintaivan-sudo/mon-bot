import AppKit
import SwiftUI
import DeskBotCore

/// C# SettingsPanel: island хэмжээ/байрлал, behavior, login item, hotkey, privacy. Бүгд real-time,
/// settings.json-д debounce-тэй хадгалагдана.
struct SettingsPanel: View {
    let deps: ControlCenterDeps
    @State private var hotkey = ""
    @State private var hotkeyStatus: String?
    @State private var hotkeyOK = true
    @State private var loginStatus = ""
    @State private var loginError: String?

    var body: some View {
        @Bindable var s = deps.settings
        HStack(alignment: .top, spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    SectionTitle("Dynamic Island")
                    Caption("Display")
                    Picker("", selection: $s.dockScreen) {
                        Text("Main display").tag("")
                        ForEach(NSScreen.screens, id: \.self) { screen in
                            Text(screen.localizedName).tag(ScreenProvider.id(of: screen))
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .onChange(of: s.dockScreen) { s.offsetX = 0; s.topOffset = 0 }
                    SliderRow(title: "Collapsed width", value: $s.islandWidth, range: 120...400, step: 2, format: "%.0f")
                    SliderRow(title: "Height", value: $s.islandHeight, range: 26...60, step: 1, format: "%.0f")
                    SliderRow(title: "Hover width", value: $s.hoverWidth, range: 200...600, step: 2, format: "%.0f")
                    SliderRow(title: "Panel width", value: $s.panelWidth, range: 480...1000, step: 10, format: "%.0f")
                    SliderRow(title: "Panel height", value: $s.panelHeight, range: 320...800, step: 10, format: "%.0f")
                    SliderRow(title: "Corner radius", value: $s.cornerRadius, range: 0...30, step: 1, format: "%.0f")
                    SliderRow(title: "Opacity", value: $s.backgroundOpacity, range: 0.4...1)
                    SliderRow(title: "Top offset (0 = notch / edge)", value: $s.topOffset, range: 0...200, step: 1, format: "%.0f")
                    SliderRow(title: "Auto-collapse (ms)", value: intBinding($s.autoCollapseMs), range: 0...3000, step: 50, format: "%.0f")
                    SliderRow(title: "Hover delay (ms)", value: intBinding($s.hoverDelayMs), range: 0...800, step: 10, format: "%.0f")
                    HStack {
                        Caption("Background")
                        Picker("", selection: $s.background) {
                            ForEach(IslandBackground.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden().controlSize(.small).frame(width: 130)
                    }
                    SmallButton("Reset position", action: deps.resetPosition)
                }
                .padding(.trailing, 6)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    SectionTitle("Behavior")
                    ToggleRow(title: "Pinned — panel stays open on outside click", isOn: $s.pinned)
                    ToggleRow(title: "Auto-hide — slides up when unused", isOn: $s.autoHide)
                    ToggleRow(title: "Lock position", isOn: $s.lockPosition)
                    ToggleRow(title: "Game mode — hide over fullscreen apps", isOn: $s.gameModeAutoHide)
                    ToggleRow(title: "Performance mode (no glow, 30 fps)", isOn: $s.performanceMode)
                    ToggleRow(title: "Start at login", isOn: loginBinding, detail: loginError ?? loginStatus)

                    SectionTitle("Global shortcut")
                    HStack(spacing: 6) {
                        TextField("Ctrl+Option+Space", text: $hotkey).field().frame(width: 150).onSubmit(applyHotkey)
                        SmallButton("Apply", action: applyHotkey)
                    }
                    if let hotkeyStatus {
                        Text(hotkeyStatus).font(.system(size: 11)).foregroundStyle(hotkeyOK ? CC.secondary : CC.danger)
                    }
                    Caption("Toggles the control center. Examples: Ctrl+Option+Space, Ctrl+Shift+D, Cmd+Option+K. ⌥/⇧-only combos are rejected — they type characters.")

                    SectionTitle("Data & privacy")
                    Caption("Settings and reminders stay on this Mac. DeskBot never reads the keyboard (the shortcut is registered with the system), never records the screen and sends nothing to any server. Mouse position is used only for the eye animation.")
                    HStack(spacing: 6) {
                        SmallButton("Data folder") { open(SettingsStore.directory) }
                        SmallButton("Logs") { open(Log.directory) }
                    }
                    Caption("DeskBot \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                }
                .padding(.trailing, 6)
            }
        }
        .onAppear {
            hotkey = deps.settings.hotkey
            hotkeyStatus = nil
            refreshLogin()
        }
    }

    private func intBinding(_ b: Binding<Int>) -> Binding<Double> {
        Binding(get: { Double(b.wrappedValue) }, set: { b.wrappedValue = Int($0.rounded()) })
    }

    /// Toggle нь хэрэглэгчийн хүсэл (settings); бодит төлөв SMAppService-ээс.
    private var loginBinding: Binding<Bool> {
        Binding(get: { deps.settings.startAtLogin }, set: { on in
            deps.settings.startAtLogin = on
            loginError = LoginItemService.set(on)
            refreshLogin()
        })
    }

    private func refreshLogin() { loginStatus = LoginItemService.statusText }

    private func applyHotkey() {
        if let err = deps.applyHotkey(hotkey) {
            hotkeyOK = false
            hotkeyStatus = err
        } else {
            hotkeyOK = true
            hotkey = deps.settings.hotkey
            hotkeyStatus = "Registered \((try? HotkeySpec.parse(hotkey))?.symbols ?? hotkey)"
        }
    }

    private func open(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}
