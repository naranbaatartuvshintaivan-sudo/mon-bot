import SwiftUI
import DeskBotCore

/// Collapsed island: дээд булан шулуун, доод булан бөөрөнхий хар pill.
/// Notch-тэй бол notch-ийг бүрэн тойроод нүд нь хоёр талын "чих"-нд байрлана.
struct IslandView: View {
    let model: IslandModel

    var body: some View {
        let layout = model.layout
        let size = layout.frame.size
        let r = min(model.cornerRadius, size.height / 2)

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

            ForEach(eyeCenters(size: size, notch: layout.notchInIsland), id: \.x) { c in
                PlaceholderEye()
                    .frame(width: eyeSize(size).width, height: eyeSize(size).height)
                    .position(c)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func eyeSize(_ s: CGSize) -> CGSize {
        let h = (s.height * 0.5).rounded()
        return CGSize(width: (h * 0.8).rounded(), height: h)
    }

    /// SwiftUI координат (origin дээд зүүн).
    private func eyeCenters(size: CGSize, notch: CGRect?) -> [CGPoint] {
        let y = size.height / 2
        if let n = notch {
            return [CGPoint(x: n.minX / 2, y: y), CGPoint(x: (n.maxX + size.width) / 2, y: y)]
        }
        let gap = eyeSize(size).width * 1.6
        return [CGPoint(x: size.width / 2 - gap / 2, y: y), CGPoint(x: size.width / 2 + gap / 2, y: y)]
    }
}

/// M1 placeholder — M2-д RobotFaceView (Canvas + TimelineView)-ээр солигдоно.
private struct PlaceholderEye: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color(red: 0x33 / 255, green: 0xE1 / 255, blue: 1))
            .shadow(color: Color(red: 0x33 / 255, green: 0xE1 / 255, blue: 1).opacity(0.6), radius: 3)
    }
}
