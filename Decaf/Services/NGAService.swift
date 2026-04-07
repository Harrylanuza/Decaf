import Foundation

/// Serves public-domain paintings from the National Gallery of Art, Washington.
///
/// The NGA does not provide a REST query API. Instead, their open-access programme
/// publishes CC0-licensed CSV datasets on GitHub. Those CSVs have been pre-processed
/// into `nga_paintings.json` (bundled with the app), which contains the 2 825
/// paintings that are:
///   - tagged Technique = "painted surface" in objects_terms.csv
///   - marked openaccess = 1 with viewtype = primary in published_images.csv
///   - within the portrait-friendly aspect-ratio range (0.4–2.0) with a minimum
///     short side of 400 px (dimensions are included in published_images.csv so
///     no IIIF info.json probe is needed at runtime)
///
/// Images are served via the NGA's IIIF endpoint — no API key required:
///   https://api.nga.gov/iiif/{uuid}/full/843,/0/default.jpg
///
/// The bundle JSON should be regenerated from the upstream CSVs when a new app
/// version is released to pick up newly open-accessed works.
struct NGAService {
    static let shared = NGAService()

    private static let imageBase = "https://api.nga.gov/iiif"
    private static let imageSize = "843,"   // 843 px wide, height proportional

    // MARK: - Bundle record type

    private struct NGARecord: Decodable {
        let id: String
        let title: String
        let artist: String
        let date: String
        let medium: String
        let credit: String
        let iiifUUID: String
    }

    // Full painting pool loaded once from the bundle — nil only if the JSON
    // is missing (should never happen in a correctly built app).
    private let pool: [NGARecord]

    private init() {
        guard let url  = Bundle.main.url(forResource: "nga_paintings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([NGARecord].self, from: data)
        else {
            pool = []
            return
        }
        pool = records
    }

    // MARK: - Public API

    /// Returns a random selection of public-domain NGA paintings.
    /// Entirely synchronous — all metadata is in the bundle, no network calls needed.
    func fetchRandomPaintings(count: Int = 10) -> [Artwork] {
        pool
            .shuffled()
            .prefix(count)
            .compactMap(artwork(from:))
    }

    // MARK: - Private

    private func artwork(from record: NGARecord) -> Artwork? {
        guard let imageURL = URL(string: "\(NGAService.imageBase)/\(record.iiifUUID)/full/\(NGAService.imageSize)/0/default.jpg")
        else { return nil }

        return Artwork(
            id:         "nga-\(record.id)",
            imageURL:   imageURL,
            title:      record.title.isEmpty ? "Untitled" : record.title,
            artistName: record.artist.isEmpty ? "Unknown Artist" : record.artist,
            date:       record.date,
            credit:     "National Gallery of Art, Washington",
            museumURL:  URL(string: "https://www.nga.gov/collection/art-object-page.\(record.id).html")
        )
    }
}
