import SwiftUI
import DeskBotCore

/// Collapsed island: дээд булан шулуун, доод булан бөөрөнхий хар pill.
/// - Notch-гүй: robot нүүр (C#-ийн header-тэй ижил 112pt өргөн) pill-ийн төвд.
/// - Notch-тэй: нүүр island-ийн бүх өргөнийг эзэлж, нүд нь notch-ийн хоёр талын "чих"-ний төвд.
struct IslandView: View {
    /// C# IslandWindow.xaml: `<controls:RobotFace Width="112" Margin="0,1" />`
    static let faceWidth: CGFloat = 112
    static let faceMarginY: CGFloat = 1

    let model: IslandModel
    let face: FaceDriver

    var body: some View {
        let layout = model.layout
        let size = layout.frame.size
        let r = min(model.cornerRadius, size.height / 2)
        let faceH = max(0, size.height - 2 * Self.faceMarginY)

        ZStack(alignment: .topLeading) {
            UnevenRoundedRectangle(bottomLeadingRadius: r, bottomTrailingRadius: r, style: .continuous)
                .fill(Color.black)

            if model.simulatedNotch, let n = layout.notchInIsland {
                // Debug: хуурамч notch-ийн хил (жинхэнэ notch дээр харагдахгүй)
                Rectangle()
                    .strokeBorder(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: n.width, height: n.height)
                    .offset(x: n.minX, y: size.height - n.maxY)
            }

            if let n = layout.notchInIsland {
                // Чихний төвүүд: n.minX/2 ба (n.maxX + W)/2 → хоорондын зай
                let spacing = Double((n.maxX + size.width) / 2 - n.minX / 2)
                RobotFaceView(driver: face, spacingOverride: spacing, paused: !model.faceVisible)
                    .frame(width: size.width, height: faceH)
                    .position(x: size.width / 2, y: size.height / 2)
            } else {
                RobotFaceView(driver: face, paused: !model.faceVisible)
                    .frame(width: min(Self.faceWidth, size.width), height: faceH)
                    .position(x: size.width / 2, y: size.height / 2)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
