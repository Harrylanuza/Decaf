import SwiftUI
import SwiftData

struct FavoritesView: View {
    @Query(sort: \FavoriteItem.savedAt, order: .reverse)
    private var favorites: [FavoriteItem]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                if validFavorites.isEmpty {
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

    private var validFavorites: [FavoriteItem] {
        favorites.filter { URL(string: $0.imageURLString) != nil }
    }

    private var feed: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(validFavorites) { item in
                        ArtworkCard(artwork: item.asArtwork!)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
            }
            .scrollTargetBehavior(.paging)
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

                Text("Add artwork as you browse.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
