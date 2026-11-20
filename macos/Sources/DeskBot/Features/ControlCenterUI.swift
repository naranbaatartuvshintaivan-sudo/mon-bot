import SwiftUI
import DeskBotCore

/// Control center-ийн panel-уудад хэрэгтэй бүх зүйл (C# AppServices).
@MainActor
struct ControlCenterDeps {
    let settings: AppSettings
    let reminders: ReminderService
    let system: SystemMonitor
    let media: MediaService
    let expression: ExpressionState
    /// Face tab-ийн жижиг preview (island-ийн face-тэй ижил settings, тусдаа animator).
    let previewFace: FaceDriver
    var preview: (RobotExpression) -> Void = { _ in }
    /// Hotkey-г бүртгэнэ; алдаа бол мессеж.
    var applyHotkey: (String) -> String? = { _ in nil }
    var resetPosition: () -> Void = {}
}

/// Одоогийн expression (UI label-д). CompanionBrain шинэчилнэ.
@MainActor
@Observable
final class ExpressionState {
    var current: RobotExpression = .idle
}

// MARK: - Styling

enum CC {
    static let accent = Color(red: 0x33 / 255, green: 0xE1 / 255, blue: 1)
    static let amber = Color(red: 1, green: 0xB0 / 255, blue: 0x20 / 255)
    static let danger = Color(red: 1, green: 0x3B / 255, blue: 0x4A / 255)
    static let text = Color.white
    static let secondary = Color.white.opacity(0.55)
    static let muted = Color.white.opacity(0.35)
    static let card = Color.white.opacity(0.06)
}

struct Card<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CC.card))
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(CC.secondary)
            .padding(.top, 6)
    }
}

struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 11)).foregroundStyle(CC.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

struct Chip<Label: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var label: Label
    var body: some View {
        Button(action: action) {
            label
                .font(.system(size: 11.5, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(selected ? CC.accent.opacity(0.22) : Color.white.opacity(0.07)))
                .overlay(Capsule().strokeBorder(selected ? CC.accent.opacity(0.7) : .clear, lineWidth: 1))
                .foregroundStyle(selected ? CC.text : CC.text.opacity(0.75))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct SmallButton: View {
    let title: String
    var prominent = false
    var enabled = true
    let action: () -> Void
    init(_ title: String, prominent: Bool = false, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.prominent = prominent
        self.enabled = enabled
        self.action = action
    }
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(prominent ? CC.accent : Color.white.opacity(0.1)))
                .foregroundStyle(prominent ? Color.black : CC.text)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// Нэр + утга + slider (C# Ui.SliderRow).
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var format: String = "%.2f"

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(title).font(.system(size: 11)).foregroundStyle(CC.secondary)
                Spacer()
                Text(String(format: format, value)).font(.system(size: 11).monospacedDigit()).foregroundStyle(CC.text)
            }
            if let step {
                Slider(value: $value, in: range, step: step).controlSize(.mini)
            } else {
                Slider(value: $value, in: range).controlSize(.mini)
            }
        }
    }
}

struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var detail: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: $isOn) {
                Text(title).font(.system(size: 12)).foregroundStyle(CC.text)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            if let detail { Caption(detail).padding(.leading, 2) }
        }
    }
}

/// Wrap layout (chip-үүд мөр дүүрвэл доош шилжинэ).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0,
                      height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            for (i, x) in zip(row.indices, row.xs) {
                subviews[i].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y), proposal: .unspecified)
            }
        }
    }

    private struct Row { var indices: [Int] = []; var xs: [CGFloat] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        var x: CGFloat = 0, y: CGFloat = 0
        for (i, v) in subviews.enumerated() {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width {
                rows.append(row)
                y += row.height + spacing
                row = Row(y: y)
                x = 0
            }
            row.indices.append(i)
            row.xs.append(x)
            x += s.width + spacing
            row.width = x - spacing
            row.height = max(row.height, s.height)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

/// Нэг мөрийн TextField (dark).
struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.1)))
    }
}

extension View {
    func field() -> some View { modifier(FieldStyle()) }
}

enum Fmt {
    static let time: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
    static let dayTime: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE d, HH:mm"; return f }()
    static let longDate: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"; return f }()
    static let monthYear: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f }()
    static let shortDay: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM d, EEE"; return f }()
}

extension RobotExpression {
    var label: String {
        switch self {
        case .newMessage: "New message"
        case .lowBattery: "Low battery"
        default: rawValue
        }
    }
}
