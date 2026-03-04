import SwiftUI
import SwiftData

struct FeedView: View {
    @State private var artworks: [Artwork] = []
    @State private var seenIDs: Set<String> = []
    @State private var isLoading = true
    @State private var isFetchingMore = false
    @State private var fetchError: Error?

    @Environment(NetworkMonitor.self) private var network
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if isLoading {
                BrewingView()
            } else if !network.isConnected && artworks.isEmpty {
                offlineEmptyState
            } else if let fetchError, artworks.isEmpty {
                errorView(for: fetchError)
            } else {
                feed
            }
        }
        .task { await load() }
    }

    // MARK: - Subviews

    private var feed: some View {
        VerticalPageFeed(
            artworks: artworks,
            modelContainer: modelContext.container,
            onNearEnd: { Task { await fetchMore() } }
        )
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                if isFetchingMore {
                    Image(systemName: "cup.and.saucer")
                        .font(.system(size: 14, weight: .ultraLight))
                        .foregroundStyle(Theme.muted.opacity(0.5))
                        .padding(.bottom, 12)
                }
                if !network.isConnected {
                    offlineBanner
                }
            }
        }
    }

    private var offlineEmptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "cup.and.saucer")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.muted)

            VStack(spacing: 10) {
                Text("No connection.")
                    .font(.system(.callout, design: .serif))
                    .foregroundStyle(Theme.ink)

                Text("New paintings aren't available offline,\nbut your cup is still full.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .padding(.horizontal, 48)
    }

    private var offlineBanner: some View {
        Text("Offline — new paintings unavailable.")
            .font(.system(.caption2))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Theme.background.opacity(0.95))
    }

    private func errorView(for error: Error) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.muted)

            Text("Couldn't load feed")
                .font(.system(.callout, design: .serif))
                .foregroundStyle(Theme.ink)

            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Try Again") {
                Task { await load() }
            }
            .font(.system(.footnote, design: .serif))
            .foregroundStyle(Theme.body)
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .overlay(Rectangle().stroke(Theme.body.opacity(0.4), lineWidth: 0.5))
        }
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        fetchError = nil

        async let metTask   = MetService.shared.fetchRandomArtworks(count: 12)
        async let rijksTask = RijksmuseumService.shared.fetchRandomPaintings(count: 8)
        async let aicTask   = ArtInstituteService.shared.fetchRandomPaintings(count: 16)
        let met   = (try? await metTask)   ?? []
        let rijks = (try? await rijksTask) ?? []
        let aic   = (try? await aicTask)   ?? []
        print("[Feed] load() — Met: \(met.count), Rijksmuseum: \(rijks.count), AIC: \(aic.count)")
        let combined = (met + rijks + aic).shuffled()
        let fresh = combined.filter { seenIDs.insert($0.id).inserted }

        if fresh.isEmpty {
            fetchError = URLError(.cannotLoadFromNetwork)
        } else {
            artworks = fresh
        }

        isLoading = false
    }

    private func fetchMore() async {
        guard !isFetchingMore else { return }
        isFetchingMore = true

        async let metTask   = MetService.shared.fetchRandomArtworks(count: 12)
        async let rijksTask = RijksmuseumService.shared.fetchRandomPaintings(count: 8)
        async let aicTask   = ArtInstituteService.shared.fetchRandomPaintings(count: 16)
        let met   = (try? await metTask)   ?? []
        let rijks = (try? await rijksTask) ?? []
        let aic   = (try? await aicTask)   ?? []
        print("[Feed] fetchMore() — Met: \(met.count), Rijksmuseum: \(rijks.count), AIC: \(aic.count)")
        let newBatch = (met + rijks + aic).shuffled()
        let fresh = newBatch.filter { seenIDs.insert($0.id).inserted }

        if !fresh.isEmpty {
            artworks.append(contentsOf: fresh)
        }

        isFetchingMore = false
    }
}

// MARK: - VerticalPageFeed

/// UIPageViewController with .scroll transition and .vertical navigation orientation.
/// UIKit owns all layout and paging — there is no SwiftUI scroll view, no
/// GeometryReader, no .scrollTargetBehavior, and no UIAppearance involvement.
/// Each page is one UIHostingController whose root view is an ArtworkCard.
private struct VerticalPageFeed: UIViewControllerRepresentable {
    let artworks: [Artwork]
    let modelContainer: ModelContainer
    let onNearEnd: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(artworks: artworks, modelContainer: modelContainer, onNearEnd: onNearEnd)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .vertical
        )
        pvc.view.backgroundColor = .clear
        pvc.dataSource = context.coordinator
        pvc.delegate   = context.coordinator

        // Set the first page. artworks is guaranteed non-empty here because
        // FeedView only shows this view in its non-empty else branch.
        pvc.setViewControllers(
            [context.coordinator.makePage(at: 0)],
            direction: .forward,
            animated: false
        )

        return pvc
    }

    func updateUIViewController(_ pvc: UIPageViewController, context: Context) {
        let previousCount = context.coordinator.artworks.count

        // Update the coordinator before anything else so data-source callbacks
        // that fire during setViewControllers see the fresh array.
        context.coordinator.artworks  = artworks
        context.coordinator.onNearEnd = onNearEnd

        // When a fetchMore batch arrives, UIPageViewController still holds a
        // stale nil in its adjacent-page cache from the last call to
        // viewControllerAfter that returned nil (the old end of the list).
        // UIKit never re-queries the data source on its own, so the user hits
        // a permanent hard stop even though new pages now exist.
        //
        // Re-presenting the current page without animation flushes that cache,
        // causing UIKit to immediately re-call viewControllerAfter with the
        // current index and get a valid page back.
        if artworks.count > previousCount,
           let currentVC = pvc.viewControllers?.first {
            pvc.setViewControllers([currentVC], direction: .forward, animated: false)
        }
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var artworks: [Artwork]
        let modelContainer: ModelContainer
        var onNearEnd: () -> Void

        init(artworks: [Artwork], modelContainer: ModelContainer, onNearEnd: @escaping () -> Void) {
            self.artworks       = artworks
            self.modelContainer = modelContainer
            self.onNearEnd      = onNearEnd
        }

        /// Builds a hosting controller for the artwork at the given index.
        /// The view.tag stores the index so data-source callbacks can identify pages.
        func makePage(at index: Int) -> UIViewController {
            let vc = UIHostingController(
                rootView: ArtworkCard(artwork: artworks[index])
                    .modelContainer(modelContainer)
                    .ignoresSafeArea()
            )
            vc.view.tag             = index
            vc.view.backgroundColor = .clear
            return vc
        }

        // MARK: UIPageViewControllerDataSource

        func pageViewController(
            _ pvc: UIPageViewController,
            viewControllerBefore vc: UIViewController
        ) -> UIViewController? {
            let index = vc.view.tag
            guard index > 0 else { return nil }
            return makePage(at: index - 1)
        }

        func pageViewController(
            _ pvc: UIPageViewController,
            viewControllerAfter vc: UIViewController
        ) -> UIViewController? {
            let index = vc.view.tag

            // Fire before the bounds check so onNearEnd() is called even when
            // the user is already on the last page. Without this ordering,
            // the guard would return nil first and the fetch would never start.
            // Trigger 5 pages from the end (not 3) to give the network request
            // enough lead time to complete before the user reaches the boundary.
            if index >= artworks.count - 5 {
                onNearEnd()
            }

            guard index < artworks.count - 1 else { return nil }
            return makePage(at: index + 1)
        }
    }
}

#Preview {
    FeedView()
        .environment(NetworkMonitor())
}
