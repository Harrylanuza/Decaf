import SwiftUI
import SwiftData

struct FavoriteButton: View {
    let artwork: Artwork

    @Environment(\.modelContext) private var context
    @Query private var matches: [FavoriteItem]

    init(artwork: Artwork) {
        self.artwork = artwork
        let id = artwork.id
        _matches = Query(filter: #Predicate<FavoriteItem> { $0.artworkID == id })
    }

    private var isFavorited: Bool { !matches.isEmpty }

    var body: some View {
        Button(action: toggle) {
            Image(systemName: "cup.and.saucer")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(isFavorited ? Theme.ink : Theme.muted)
                .animation(.easeInOut(duration: 0.2), value: isFavorited)
        }
        .frame(width: 44, height: 44)
        .padding(.trailing, 20)
    }

    private func toggle() {
        if let existing = matches.first {
            // Remove local image file before deleting the record.
            ImageStore.delete(for: existing.artworkID)
            context.delete(existing)
        } else {
            let item = FavoriteItem(from: artwork)
            context.insert(item)
            // Download and cache the image in the background so the artwork
            // is fully available offline.  The insert is immediate so the UI
            // responds instantly; localImagePath is set once the file is ready.
            Task {
                if let path = try? await ImageStore.save(
                    imageAt: artwork.imageURL,
                    artworkID: artwork.id
                ) {
                    item.localImagePath = path
                }
            }
        }
    }
}
