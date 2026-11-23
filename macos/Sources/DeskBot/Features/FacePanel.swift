import SwiftUI
import DeskBotCore

/// C# FacePanel: mood (base), expression preview (Preview layer 45, 3с), theme, eye shape, slider-ууд.
/// Жижиг preview нь island-ийн face-тэй ижил settings-ийг хуваалцана (real-time).
struct FacePanel: View {
    let deps: ControlCenterDeps
    let visible: Bool
    @State private var hex = ""

    static let moods: [RobotExpression] = [.idle, .happy, .excited, .sad, .confused, .sleepy]
    static let previews: [RobotExpression] = [.surprised, .angry, .processing, .listening, .error,
                                              .newMessage, .reminder, .lowBattery, .music, .copied]

    var body: some View {
        @Bindable var s = deps.settings
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(red: 0.012, green: 0.016, blue: 0.024))
                    FaceSlot(driver: deps.previewFace, notchWidth: nil, paused: !visible).frame(width: 240, height: 80)
                }
                .frame(height: 104)
                Text("\(deps.expression.current.label) · \(s.theme.rawValue)")
                    .font(.system(size: 11)).foregroundStyle(CC.secondary).frame(maxWidth: .infinity)
                SliderRow(title: "Eye size", value: $s.eyeSize, range: 0.5...1.6)
                SliderRow(title: "Eye spacing", value: $s.eyeSpacing, range: 0.6...1.8)
                SliderRow(title: "Glow", value: $s.glowIntensity, range: 0...1)
                SliderRow(title: "Blink frequency", value: $s.blinkFrequency, range: 0.2...3)
                SliderRow(title: "Animation speed", value: $s.animationSpeed, range: 0.25...2.5)
            }
            .frame(width: 262)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    SectionTitle("Mood (default)")
                    FlowLayout {
                        ForEach(Self.moods, id: \.self) { m in
                            Chip(selected: s.baseMood == m, action: { s.baseMood = m }) { Text(m.label) }
                        }
                    }
                    SectionTitle("Try an expression · 3 s")
                    FlowLayout {
                        ForEach(Self.previews, id: \.self) { e in
                            Chip(selected: false, action: { deps.preview(e) }) { Text(e.label) }
                        }
                    }
                    SectionTitle("Theme")
                    FlowLayout {
                        ForEach(FaceTheme.allCases, id: \.self) { t in
                            Chip(selected: s.theme == t, action: { s.theme = t }) {
                                HStack(spacing: 5) {
                                    Circle().fill(swatch(t)).frame(width: 9, height: 9)
                                    Text(t.rawValue)
                                }
                            }
                        }
                    }
                    HStack(spacing: 6) {
                        Caption("Custom color")
                        TextField("#33E1FF", text: $hex).field().frame(width: 86).onSubmit(applyHex)
                        SmallButton("Apply", action: applyHex)
                    }
                    SectionTitle("Eye shape")
                    FlowLayout {
                        ForEach(EyeShape.allCases, id: \.self) { e in
                            Chip(selected: s.eyeShape == e, action: { s.eyeShape = e }) { Text(e.rawValue) }
                        }
                    }
                    SectionTitle("Motion")
                    ToggleRow(title: "Follow cursor", isOn: $s.followCursor)
                    ToggleRow(title: "Glance at clicks anywhere", isOn: $s.reactToGlobalClicks)
                    ToggleRow(title: "Sleep after 5 min idle", isOn: $s.sleepWhenIdle)
                    ToggleRow(title: "Reduced motion", isOn: $s.reducedMotion)
                    SectionTitle("Reactions")
                    ToggleRow(title: "✓ when I copy something", isOn: $s.reactToCopy)
                    ToggleRow(title: "Loading face while an app opens", isOn: $s.reactToAppLaunch)
                    ToggleRow(title: "Loading face while downloading (asks for Downloads access)", isOn: $s.reactToDownloads)
                }
                .padding(.trailing, 6)
            }
        }
        .onAppear { hex = deps.settings.customColor }
    }

    private func applyHex() {
        var v = hex.trimmingCharacters(in: .whitespaces)
        if !v.hasPrefix("#") { v = "#" + v }
        if AppSettings.isHexColor(v) {
            deps.settings.customColor = v.uppercased()
            deps.settings.theme = .custom
        }
        hex = deps.settings.customColor
    }

    private func swatch(_ t: FaceTheme) -> AnyShapeStyle {
        switch t {
        case .aurora: AnyShapeStyle(LinearGradient(colors: [Color(red: 0.2, green: 0.88, blue: 1), Color(red: 0.66, green: 0.36, blue: 1)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        case .glitch: AnyShapeStyle(LinearGradient(colors: [Color(red: 0.49, green: 0.97, blue: 1), Color(red: 1, green: 0.24, blue: 0.96)],
                                                   startPoint: .leading, endPoint: .trailing))
        default: AnyShapeStyle(FacePalette.themeColor(t, time: 0, customHex: deps.settings.customColor).color)
        }
    }
}
