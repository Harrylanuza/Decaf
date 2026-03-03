import SwiftUI

/// Replaces the default loading spinner while artwork images are being fetched.
/// Three steam wisps rise and fade in a slow, staggered loop above a coffee cup,
/// evoking the calm of waiting for something good.
struct BrewingView: View {
    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottom) {
                SteamWisp(lean: -1, delay: 0.0)
                    .offset(x: -10)
                SteamWisp(lean:  0, delay: 0.8)
                SteamWisp(lean:  1, delay: 1.6)
                    .offset(x: 10)
            }
            .frame(width: 44, height: 40)

            Image(systemName: "cup.and.saucer")
                .font(.system(size: 26, weight: .ultraLight))
                .foregroundStyle(Theme.muted)
        }
    }
}

// MARK: - Steam wisp

private struct SteamWisp: View {
    let lean: CGFloat   // –1 curves left, 0 straight, 1 curves right
    let delay: Double

    @State private var risen = false

    var body: some View {
        SteamPath(lean: lean)
            .stroke(
                Theme.muted.opacity(risen ? 0 : 0.45),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
            )
            .frame(width: 12, height: 32)
            .offset(y: risen ? -14 : 0)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 2.2)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) {
                    risen = true
                }
            }
    }
}

// MARK: - Wisp path (gentle S-curve)

private struct SteamPath: Shape {
    let lean: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let x = rect.midX
        let c = 3.5 * lean   // horizontal amplitude of the curve

        p.move(to: CGPoint(x: x, y: rect.maxY))
        p.addCurve(
            to: CGPoint(x: x + c, y: rect.midY),
            control1: CGPoint(x: x - c * 0.6, y: rect.maxY - 10),
            control2: CGPoint(x: x + c,        y: rect.midY + 8)
        )
        p.addCurve(
            to: CGPoint(x: x - c * 0.3, y: rect.minY),
            control1: CGPoint(x: x + c * 0.5,  y: rect.midY - 6),
            control2: CGPoint(x: x - c,         y: rect.minY + 10)
        )
        return p
    }
}

#Preview {
    BrewingView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
}
