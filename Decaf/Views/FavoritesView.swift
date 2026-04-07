import SwiftUI
import SwiftData

struct FavoritesView: View {
    @Query(sort: \FavoriteItem.savedAt, order: .reverse)
    private var favorites: [FavoriteItem]

    @State private var selectedItem: FavoriteItem?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if validFavorites.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .fullScreenCover(item: $selectedItem) { item in
            if let artwork = item.asArtwork {
                CupDetailView(artwork: artwork)
            } else {
                // Fallback: asArtwork returned nil (malformed URL). Show a
                // dismiss button so the user is never trapped on a blank screen.
                ZStack {
                    Theme.background.ignoresSafeArea()
                    Button { selectedItem = nil } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .light))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 60)
                    .padding(.leading, 12)
                }
            }
        }
    }

    // MARK: - Subviews

    private var validFavorites: [FavoriteItem] {
        favorites.filter { URL(string: $0.imageURLString) != nil }
    }

    private var grid: some View {
        // Use 4 columns on iPad (regular width) and 2 on iPhone (compact).
        let columnCount = horizontalSizeClass == .regular ? 4 : 2
        let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: columnCount)
        return ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(validFavorites) { item in
                    ThumbnailCell(item: item)
                        .aspectRatio(1, contentMode: .fit)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedItem = item }
                }
            }
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

// MARK: - Thumbnail cell

private struct ThumbnailCell: View {
    let item: FavoriteItem

    var body: some View {
        // Color.clear establishes the proposed square frame; AsyncImage overlays
        // and fills it with scaledToFill. clipped() crops any overflow.
        Color.clear
            .overlay {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .empty:
                        Theme.muted.opacity(0.08)
                    case .failure:
                        Theme.muted.opacity(0.15)
                    @unknown default:
                        Color.clear
                    }
                }
            }
            .clipped()
    }

    private var imageURL: URL? {
        if let path = item.localImagePath, let local = ImageStore.fileURL(for: path) {
            return local
        }
        return URL(string: item.imageURLString)
    }
}

// MARK: - Full-screen detail

private struct CupDetailView: View {
    let artwork: Artwork
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // ignoresSafeArea() is applied directly to ArtworkCard — the same way
        // VerticalPageFeed does it via UIHostingController. This lets the card's
        // own internal safe-area accounting work correctly; wrapping it in an
        // outer GeometryReader causes the card to double-count the top inset,
        // pushing the painting too far down.
        ArtworkCard(artwork: artwork)
            .ignoresSafeArea()
            .overlay(alignment: .topLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Sit just below the Dynamic Island / status bar.
                .padding(.top, 60)
                .padding(.leading, 12)
            }
            // Swipe down to dismiss — intuitive complement to the close button.
            .gesture(DragGesture().onEnded { value in
                if value.translation.height > 80 { dismiss() }
            })
    }
}
