import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .discover
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    enum Tab { case discover, cup }

    // iPad (.regular) uses a taller bar to match its larger touch targets and
    // proportionally larger safe-area insets at the bottom.
    private var tabBarHeight: CGFloat { horizontalSizeClass == .regular ? 60 : 49 }

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

    private var content: some View {
        // ZStack keeps both views alive so UIPageViewController retains its
        // current page across tab switches. A @ViewBuilder switch destroys
        // FeedView on every tab change, resetting the scroll position and
        // triggering a reload. opacity + allowsHitTesting gives a clean
        // show/hide without any SwiftUI appear/disappear lifecycle events.
        ZStack {
            FeedView()
                .opacity(selectedTab == .discover ? 1 : 0)
                .allowsHitTesting(selectedTab == .discover)
            FavoritesView()
                .opacity(selectedTab == .cup ? 1 : 0)
                .allowsHitTesting(selectedTab == .cup)
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
            .frame(height: tabBarHeight)
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
                .frame(height: tabBarHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
        .environment(NetworkMonitor())
}
