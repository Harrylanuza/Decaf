import SwiftUI

/// Renders the Decaf app icon at exactly 1024×1024 using SwiftUI.
///
/// Usage: open the #Preview below in Xcode, resize the canvas to 1024×1024,
/// then screenshot it (or use Xcode's export) to produce AppIcon.png.
struct AppIconPreview: View {
    private let brown = Color(red: 139/255, green: 94/255, blue: 60/255)
    private let linen = Color(red: 245/255, green: 240/255, blue: 232/255)

    var body: some View {
        ZStack {
            linen

            // Steam wisps — centered above the cup opening
            SteamWispsShape(brown: brown)
                .offset(y: -155)

            Image(systemName: "cup.and.saucer")
                .font(.system(size: 420, weight: .thin))
                .foregroundStyle(brown.opacity(0.8))
                .offset(y: 35)
        }
        .frame(width: 1024, height: 1024)
    }
}

// MARK: - Steam Wisps

private struct SteamWispsShape: View {
    let brown: Color

    var body: some View {
        Canvas { ctx, size in
            // Three sinusoidal wisps spread across the cup opening
            let wisps: [(dx: Double, topFrac: Double, phase: Double)] = [
                (dx: -72, topFrac: 0.22, phase: 0.0),
                (dx:   0, topFrac: 0.00, phase: 1.1),
                (dx:  72, topFrac: 0.18, phase: 2.2),
            ]

            let shading = GraphicsContext.Shading.color(brown.opacity(0.45))

            for wisp in wisps {
                let cx     = size.width / 2 + wisp.dx
                let botY   = size.height
                let topY   = size.height * wisp.topFrac
                let amp    = 14.0

                var path = Path()
                let steps = 100
                for i in 0 ... steps {
                    let t  = Double(i) / Double(steps)
                    let y  = botY + (topY - botY) * t
                    let x  = cx + amp * sin(wisp.phase + t * .pi * 3.5)
                    let pt = CGPoint(x: x, y: y)
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }

                ctx.stroke(
                    path,
                    with: shading,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(width: 220, height: 200)
    }
}

// MARK: - Preview

#Preview("App Icon — 1024×1024") {
    AppIconPreview()
}
