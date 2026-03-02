import Foundation
import SwiftData

@Model
final class FavoriteItem {
    var artworkID: String
    var title: String
    var artistOrAuthor: String
    var date: String
    var imageURLString: String
    var credit: String
    var savedAt: Date

    init(from artwork: Artwork) {
        self.artworkID      = artwork.id
        self.title          = artwork.title
        self.artistOrAuthor = artwork.artistName
        self.date           = artwork.date
        self.imageURLString = artwork.imageURL.absoluteString
        self.credit         = artwork.credit
        self.savedAt        = Date()
    }

    var asArtwork: Artwork? {
        guard let url = URL(string: imageURLString) else { return nil }
        return Artwork(id: artworkID, imageURL: url, title: title, artistName: artistOrAuthor, date: date, credit: credit)
    }
}
