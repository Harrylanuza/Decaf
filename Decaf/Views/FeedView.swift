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
                loadingCard
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
            onNearEnd: { Task { await fetchMore() } },
            onImageFailure: { id in
                // Remove the artwork whose image failed and mark it seen so
                // it is never re-fetched; the user never sees the broken card.
                artworks.removeAll { $0.id == id }
                seenIDs.insert(id)
            }
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

    /// Structural skeleton that mirrors ArtworkCard's layout so BrewingView
    /// occupies the identical frame during the API-fetch loading phase as it does
    /// during ArtworkCard's image-download phase. Uses the same GeometryReader,
    /// ignoresSafeArea, caption fonts, and padding as ArtworkCard so there is
    /// zero positional jump when the feed transitions in.
    private var loadingCard: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                BrewingView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)

                // Caption block — same structure as ArtworkCard.caption.
                // Single-space Text views preserve the correct line height for
                // each style without displaying visible content.
                VStack(alignment: .leading, spacing: 0) {
                    Theme.hairline
                        .frame(maxWidth: .infinity)
                        .frame(height: 0.5)
                        .padding(.horizontal, 28)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(verbatim: " ").font(.system(.callout,  design: .serif))
                        Text(verbatim: " ").font(.system(.footnote, design: .serif))
                        Text(verbatim: " ").font(.system(.caption2))
                        Text(verbatim: " ").font(.system(.caption2).italic()).padding(.top, 6)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .background(Theme.background)
            .clipped()
        }
        .ignoresSafeArea(edges: .top)
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
        // Skip if artworks are already loaded. With the ZStack-based tab layout
        // in ContentView, FeedView is never recreated on tab switches, so this
        // guard is mainly a safety net against unexpected task re-fires.
        guard artworks.isEmpty else { return }
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
    let onImageFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            artworks: artworks,
            modelContainer: modelContainer,
            onNearEnd: onNearEnd,
            onImageFailure: onImageFailure
        )
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
        let coordinator      = context.coordinator
        let previousArtworks = coordinator.artworks
        let previousCount    = previousArtworks.count
        let savedIndex       = coordinator.currentIndex

        // Update the coordinator before anything else so data-source callbacks
        // that fire during setViewControllers see the fresh array.
        coordinator.artworks       = artworks
        coordinator.onNearEnd      = onNearEnd
        coordinator.onImageFailure = onImageFailure

        if artworks.count > previousCount {
            // When a fetchMore batch arrives, UIPageViewController still holds a
            // stale nil in its adjacent-page cache from the last call to
            // viewControllerAfter that returned nil (the old end of the list).
            // Re-presenting the page at savedIndex flushes that cache. Using the
            // delegate-tracked index (not pvc.viewControllers?.first) is safer:
            // the pvc's array can be transiently nil after visibility changes.
            guard savedIndex < artworks.count else { return }
            let vc = pvc.viewControllers?.first ?? coordinator.makePage(at: savedIndex)
            pvc.setViewControllers([vc], direction: .forward, animated: false)

        } else if artworks.count < previousCount {
            // An artwork was removed (its image failed). Find the index of the
            // removed artwork by scanning for the first position where old and
            // new arrays diverge. If the removal fell before the current page,
            // every subsequent index shifts left by one — compensate so the user
            // stays on the same painting rather than jumping forward one.
            guard !artworks.isEmpty else { return }
            var removedIndex = previousCount - 1
            for i in artworks.indices {
                if artworks[i].id != previousArtworks[i].id {
                    removedIndex = i
                    break
                }
            }
            let adjustedIndex = removedIndex < savedIndex ? savedIndex - 1 : savedIndex
            let targetIndex = min(adjustedIndex, artworks.count - 1)
            coordinator.currentIndex = targetIndex
            pvc.setViewControllers(
                [coordinator.makePage(at: targetIndex)],
                direction: .forward,
                animated: false
            )

        }
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var artworks: [Artwork]
        let modelContainer: ModelContainer
        var onNearEnd: () -> Void
        var onImageFailure: (String) -> Void
        /// The index of the page the user last settled on. Updated by the
        /// delegate so updateUIViewController always has a reliable position
        /// to restore — even if UIPageViewController's viewControllers array
        /// is transiently empty after a visibility-state change.
        var currentIndex: Int = 0

        init(
            artworks: [Artwork],
            modelContainer: ModelContainer,
            onNearEnd: @escaping () -> Void,
            onImageFailure: @escaping (String) -> Void
        ) {
            self.artworks       = artworks
            self.modelContainer = modelContainer
            self.onNearEnd      = onNearEnd
            self.onImageFailure = onImageFailure
        }

        /// Builds a hosting controller for the artwork at the given index.
        /// The view.tag stores the index so data-source callbacks can identify pages.
        func makePage(at index: Int) -> UIViewController {
            let artwork = artworks[index]
            var card = ArtworkCard(artwork: artwork)
            card.onImageFailure = { [weak self] in self?.onImageFailure(artwork.id) }
            let vc = UIHostingController(
                rootView: card
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

        // MARK: UIPageViewControllerDelegate

        func pageViewController(
            _ pvc: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            // Only record the index when the swipe fully commits. A cancelled
            // swipe leaves the user on the previous page, which previousViewControllers
            // still holds, so we ignore it. This keeps currentIndex in sync with
            // what the user actually sees even during rapid or cancelled swipes.
            guard completed, let vc = pvc.viewControllers?.first else { return }
            currentIndex = vc.view.tag
        }
    }
}

#Preview {
    FeedView()
        .environment(NetworkMonitor())
}
