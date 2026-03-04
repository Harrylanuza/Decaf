import SwiftUI

struct FeedView: View {
    @State private var artworks: [Artwork] = []
    @State private var isLoading = true
    @State private var isFetchingMore = false
    @State private var fetchError: Error?

    @Environment(NetworkMonitor.self) private var network

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
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(Array(artworks.enumerated()), id: \.element.id) { index, artwork in
                    ArtworkCard(artwork: artwork)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .onAppear {
                            // Begin fetching the next batch when the user is
                            // three cards from the end — quiet, no interruption.
                            // max(0, …) guards against underflow when count < 3.
                            if index >= max(0, artworks.count - 3) {
                                Task { await fetchMore() }
                            }
                        }
                }

                // Sentinel card: holds the user's place in the paged scroll
                // while the next batch arrives. Disappears once appended.
                if isFetchingMore {
                    BrewingView()
                        .containerRelativeFrame([.horizontal, .vertical])
                        .background(Theme.background)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        // Gentle offline banner floats above the tab bar while disconnected.
        .overlay(alignment: .bottom) {
            if !network.isConnected {
                offlineBanner
            }
        }
    }

    // Shown when the device is offline and no artworks have been loaded yet.
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

    // A small, unobtrusive strip shown at the bottom of the feed when offline.
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

        // Each source is awaited independently so a failure in one does not
        // prevent the other's artworks from appearing in the feed.
        async let metTask   = MetService.shared.fetchRandomArtworks(count: 12)
        async let rijksTask = RijksmuseumService.shared.fetchRandomPaintings(count: 8)
        async let aicTask   = ArtInstituteService.shared.fetchRandomPaintings(count: 8)
        let met   = (try? await metTask)   ?? []
        let rijks = (try? await rijksTask) ?? []
        let aic   = (try? await aicTask)   ?? []
        let combined = (met + rijks + aic).shuffled()

        if combined.isEmpty {
            fetchError = URLError(.cannotLoadFromNetwork)
        } else {
            artworks = combined
        }

        isLoading = false
    }

    private func fetchMore() async {
        guard !isFetchingMore else { return }
        isFetchingMore = true

        async let metTask   = MetService.shared.fetchRandomArtworks(count: 12)
        async let rijksTask = RijksmuseumService.shared.fetchRandomPaintings(count: 8)
        async let aicTask   = ArtInstituteService.shared.fetchRandomPaintings(count: 8)
        let met   = (try? await metTask)   ?? []
        let rijks = (try? await rijksTask) ?? []
        let aic   = (try? await aicTask)   ?? []
        let newBatch = (met + rijks + aic).shuffled()

        // Only append when we actually got something; if both failed the
        // sentinel card simply disappears and the feed ends gracefully.
        if !newBatch.isEmpty {
            artworks.append(contentsOf: newBatch)
        }

        isFetchingMore = false
    }
}

#Preview {
    FeedView()
        .environment(NetworkMonitor())
}
