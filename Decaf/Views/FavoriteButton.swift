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
        .padding(.top, 20)
        .padding(.trailing, 20)
    }

    private func toggle() {
        if let existing = matches.first {
            context.delete(existing)
        } else {
            context.insert(FavoriteItem(from: artwork))
        }
    }
}
