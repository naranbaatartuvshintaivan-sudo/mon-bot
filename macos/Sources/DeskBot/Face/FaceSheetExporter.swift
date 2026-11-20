import AppKit
import SwiftUI
import DeskBotCore

/// Debug: бүх expression + cursor харц + notch хувилбарыг нэг PNG болгож offscreen зурна.
/// Screen Recording эрх шаардахгүй (ImageRenderer). `DeskBot --render-faces out.png`
@MainActor
enum FaceSheetExporter {
    private struct Cell: Identifiable {
        let id: String
        let snapshot: FaceSnapshot
        var spacingOverride: Double? = nil
        var islandWidth: CGFloat = 190
    }

    /// Deterministic: 1с урагшлуулна (transition 0.24с дууссан, анхны blink 1.5с, idle wander 6с-ээс өмнө).
    private static func animate(_ e: RobotExpression, seconds: Double = 1, cursor: SIMD2<Double>? = nil) -> FaceSnapshot {
        var a = FaceAnimator(random: { 0.5 })
        a.setExpression(e)
        if let c = cursor { a.setCursor(dx: c.x, dy: c.y) }
        for _ in 0..<Int(seconds * 60) { a.step(rawDt: 1.0 / 60) }
        return FaceSnapshot(a)
    }

    static func export(to url: URL) throws {
        var cells = RobotExpression.allCases.map { Cell(id: $0.rawValue, snapshot: animate($0)) }
        cells += [
            Cell(id: "look ← (cursor −400,0)", snapshot: animate(.idle, cursor: SIMD2(-400, 0))),
            Cell(id: "look → (cursor +400,0)", snapshot: animate(.idle, cursor: SIMD2(400, 0))),
            Cell(id: "look ↓ (cursor 0,+400)", snapshot: animate(.idle, cursor: SIMD2(0, 400))),
            Cell(id: "notice (cursor 60,20)", snapshot: animate(.idle, cursor: SIMD2(60, 20))),
            Cell(id: "blink mid (t=1.58)", snapshot: animate(.idle, seconds: 1.58)),
            Cell(id: "notch 185pt, ears", snapshot: animate(.happy), spacingOverride: Double(185 + 44), islandWidth: 273),
        ]

        let columns = 3
        let rows = stride(from: 0, to: cells.count, by: columns).map { Array(cells[$0..<min($0 + columns, cells.count)]) }
        let sheet = VStack(alignment: .leading, spacing: 10) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(alignment: .top, spacing: 14) {
                    ForEach(rows[r]) { cell in
                        VStack(spacing: 3) {
                            island(cell)
                            Text(cell.id).font(.system(size: 8)).foregroundStyle(.white.opacity(0.7))
                        }
                        .frame(width: 280)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(white: 0.16))

        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 3
        guard let cg = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
    }

    @ViewBuilder
    private static func island(_ cell: Cell) -> some View {
        let h: CGFloat = 34
        let style = FaceStyle(spacingOverride: cell.spacingOverride)
        ZStack {
            UnevenRoundedRectangle(bottomLeadingRadius: 17, bottomTrailingRadius: 17, style: .continuous)
                .fill(Color.black)
            if cell.spacingOverride != nil {
                Rectangle().fill(Color(white: 0.3)).frame(width: 185, height: h) // notch-ийн байрлал (саарал)
            }
            Canvas { ctx, size in
                FaceRenderer.draw(&ctx, size: size, snapshot: cell.snapshot, style: style)
            }
            .frame(width: cell.spacingOverride == nil ? IslandSizing().faceWidth(.collapsed) : cell.islandWidth, height: h - 2)
        }
        .frame(width: cell.islandWidth, height: h)
    }
}

/// Debug: island-ийн 4 mode (+ notch хувилбар)-ийг offscreen зурна. `DeskBot --render-island out.png`
@MainActor
enum IslandSheetExporter {
    static func export(to url: URL) throws {
        let settings = AppSettings()
        let sizing = IslandSizing(settings)
        func cell(_ mode: IslandMode, notch: CGSize? = nil, pinned: Bool = false, label: String) -> some View {
            let m = IslandModel()
            m.mode = mode
            m.islandSize = sizing.size(mode, notch: notch)
            m.headerHeight = sizing.headerHeight(mode, notch: notch)
            m.faceWidth = sizing.faceWidth(mode)
            m.notchSize = notch
            m.simulatedNotch = notch != nil
            m.cornerRadius = settings.cornerRadius + (mode == .expanded ? 8 : 0)
            m.pinned = pinned
            m.faceVisible = true
            m.alertTitle = "Test reminder"
            m.alertTime = "Reminder · 09:30"
            let driver = FaceDriver(settings: settings, random: { 0.5 })
            return VStack(spacing: 4) {
                IslandView(model: m, face: driver, actions: IslandActions())
                    .frame(width: m.islandSize.width + 2 * IslandController.padX,
                           height: m.islandSize.height + IslandController.padBottom)
                    .background(Color(white: 0.25))
                Text(label).font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
            }
        }
        let notch = CGSize(width: 185, height: 32)
        let sheet = VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                cell(.collapsed, label: "Collapsed")
                cell(.hover, label: "Hover")
                cell(.alert, label: "Alert")
            }
            HStack(alignment: .top, spacing: 14) {
                cell(.collapsed, notch: notch, label: "Collapsed · notch")
                cell(.hover, notch: notch, label: "Hover · notch")
            }
            HStack(alignment: .top, spacing: 14) {
                cell(.expanded, pinned: true, label: "Expanded · pinned")
                cell(.expanded, notch: notch, label: "Expanded · notch")
            }
        }
        .padding(14)
        .background(Color(white: 0.16))
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        guard let cg = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
    }
}
