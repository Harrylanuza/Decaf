import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var page = 0

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    slide(
                        title: "A quiet place to look\nat paintings.",
                        body: "Public domain masterworks from the Met and the Rijksmuseum — free for everyone, free from noise."
                    )
                    .tag(0)

                    slide(
                        title: "Simple by design.",
                        body: "Swipe through paintings at your own pace. Tap the cup to save anything that stays with you."
                    )
                    .tag(1)

                    finalSlide
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Page indicator and Begin button sit below the slides.
                VStack(spacing: 36) {
                    pageIndicator

                    beginButton
                        .opacity(page == 2 ? 1 : 0)
                        .allowsHitTesting(page == 2)
                        .animation(.easeInOut(duration: 0.4), value: page)
                }
                .padding(.bottom, 56)
            }
        }
    }

    // MARK: - Slides

    private func slide(title: String, body: String) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Text(title)
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)

                Text(body)
                    .font(.system(.callout))
                    .foregroundStyle(Theme.body)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
            }
            .padding(.horizontal, 48)

            Spacer()
            Spacer()
        }
    }

    // The last slide is deliberately sparse — the simplicity is the message.
    private var finalSlide: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("Take your time.")
                .font(.system(.title3, design: .serif))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Controls

    // Three thin rules — typographic rather than dot-based.
    private var pageIndicator: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { i in
                Rectangle()
                    .fill(page == i ? Theme.body : Theme.body.opacity(0.22))
                    .frame(width: 20, height: 1)
                    .animation(.easeInOut(duration: 0.2), value: page)
            }
        }
    }

    private var beginButton: some View {
        Button {
            onComplete()
        } label: {
            Text("Begin")
                .font(.system(.callout, design: .serif))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 40)
                .padding(.vertical, 13)
                .overlay(Rectangle().stroke(Theme.ink.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    OnboardingView { }
}
