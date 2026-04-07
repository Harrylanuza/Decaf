import Foundation
import SwiftData

@Model
final class FavoriteItem {
    var artworkID: String
    var title: String
    var artistOrAuthor: String
    var date: String
    var imageURLString: String   // remote URL; kept as offline fallback
    var localImagePath: String?  // relative path inside Application Support
    var credit: String
    var museumURLString: String?
    var savedAt: Date

    init(from artwork: Artwork) {
        self.artworkID       = artwork.id
        self.title           = artwork.title
        self.artistOrAuthor  = artwork.artistName
        self.date            = artwork.date
        self.imageURLString  = artwork.imageURL.absoluteString
        self.localImagePath  = nil   // set asynchronously after download
        self.credit          = artwork.credit
        self.museumURLString = artwork.museumURL?.absoluteString
        self.savedAt         = Date()
    }

    /// Returns an `Artwork` value for displaying this favourite.
    /// Prefers the locally cached image so the card loads instantly and
    /// works without a network connection; falls back to the remote URL
    /// if the local file has not been downloaded yet.
    var asArtwork: Artwork? {
        let imageURL: URL
        if let path = localImagePath, let local = ImageStore.fileURL(for: path) {
            imageURL = local
        } else {
            guard let remote = URL(string: imageURLString) else { return nil }
            imageURL = remote
        }
        return Artwork(
            id: artworkID,
            imageURL: imageURL,
            title: title,
            artistName: artistOrAuthor,
            date: date,
            credit: credit,
            museumURL: museumURLString.flatMap(URL.init)
        )
    }
}
