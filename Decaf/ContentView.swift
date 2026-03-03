import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .discover
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    enum Tab { case discover, cup }

    var body: some View {
        ZStack {
            content
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    tabBar
                }

            if !hasSeenOnboarding {
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        hasSeenOnboarding = true
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .discover: FeedView()
        case .cup:      FavoritesView()
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        VStack(spacing: 0) {
            // Hairline separator — same design token used in ArtworkCard captions.
            Theme.hairline
                .frame(height: 0.5)

            HStack(spacing: 0) {
                tabButton(for: .discover, icon: "rectangle.stack")
                tabButton(for: .cup,      icon: "cup.and.saucer")
            }
            .frame(height: 49)
        }
        // Extend linen behind the home-indicator safe area so the bar
        // blends seamlessly to the screen edge.
        .background(Theme.background.ignoresSafeArea(edges: .bottom))
    }

    private func tabButton(for tab: Tab, icon: String) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(selectedTab == tab
                    ? Theme.body
                    : Theme.body.opacity(0.32))
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
                .frame(maxWidth: .infinity)
                .frame(height: 49)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
}
