import SwiftUI

struct FeedView: View {
    @State private var artworks: [Artwork] = []
    @State private var isLoading = true
    @State private var fetchError: Error?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(Theme.muted)
            } else if let fetchError {
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
                ForEach(artworks) { artwork in
                    ArtworkCard(artwork: artwork)
                        .containerRelativeFrame([.horizontal, .vertical])
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
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
        do {
            // Fetch from both museums concurrently; failures in either are tolerated.
            async let metPaintings  = MetService.shared.fetchRandomArtworks(count: 12)
            async let rijksPaintings = RijksmuseumService.shared.fetchRandomPaintings(count: 8)

            let (met, rijks) = try await (metPaintings, rijksPaintings)
            artworks = (met + rijks).shuffled()
        } catch {
            fetchError = error
        }
        isLoading = false
    }
}

#Preview {
    FeedView()
}
