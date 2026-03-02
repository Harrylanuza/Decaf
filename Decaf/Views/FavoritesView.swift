import SwiftUI
import SwiftData

struct FavoritesView: View {
    @Query(sort: \FavoriteItem.savedAt, order: .reverse)
    private var favorites: [FavoriteItem]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                if favorites.isEmpty {
                    emptyState
                } else {
                    feed
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Your Cup")
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(Theme.body)
                }
            }
        }
    }

    // MARK: - Subviews

    private var feed: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(favorites) { item in
                    card(for: item)
                        .containerRelativeFrame([.horizontal, .vertical])
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
    }

    @ViewBuilder
    private func card(for item: FavoriteItem) -> some View {
        if let artwork = item.asArtwork {
            ArtworkCard(artwork: artwork)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "cup.and.saucer")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.muted)

            VStack(spacing: 8) {
                Text("Your cup is empty.")
                    .font(.system(.callout, design: .serif))
                    .foregroundStyle(Theme.ink)

                Text("Add artworks\nas you browse.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
