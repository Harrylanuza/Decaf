import Foundation

/// Serves public-domain paintings from the Walters Art Museum, Baltimore.
///
/// The Walters v1 REST API was shut down in 2023. Their open-access programme
/// publishes CC0-licensed CSV datasets on GitHub:
///   https://github.com/WaltersArtMuseum/api-thewalters-org
///
/// Those CSVs have been pre-processed into `walters_paintings.json` (bundled
/// with the app), which contains the 1 670 works that are:
///   - Classification = "Painting & Drawing" in art.csv
///   - ObjectName contains "painting", "portrait", or "watercolor"
///   - ObjectName does not contain scroll, album, folio, tangka, kakemono,
///     emakimono, mummy portrait, death mask, banner, or fan
///   - IsPrimary = 1 in media.csv (one canonical image per work)
///
/// Images are served directly from the Walters CDN — no API key required:
///   https://art.thewalters.org/images/raw/{filename}
///
/// The bundle JSON should be regenerated from the upstream CSVs when a new
/// app version is released to pick up newly accessioned works.
struct WaltersService {
    static let shared = WaltersService()

    // MARK: - Bundle record type

    private struct WaltersRecord: Decodable {
        let id: String
        let title: String
        let artist: String
        let date: String
        let medium: String
        let imageURL: String
    }

    // Full painting pool loaded once from the bundle — empty only if the JSON
    // is missing (should never happen in a correctly built app).
    private let pool: [WaltersRecord]

    private init() {
        guard let url     = Bundle.main.url(forResource: "walters_paintings", withExtension: "json"),
              let data    = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([WaltersRecord].self, from: data)
        else {
            #if DEBUG
            print("⚠️ WaltersService: failed to load walters_paintings.json from bundle")
            #endif
            pool = []
            return
        }
        pool = records
    }

    // MARK: - Public API

    /// Returns a random selection of public-domain Walters paintings.
    /// Entirely synchronous — all metadata is in the bundle, no network calls needed.
    func fetchRandomPaintings(count: Int = 10) -> [Artwork] {
        pool
            .shuffled()
            .prefix(count)
            .compactMap(artwork(from:))
    }

    // MARK: - Private

    private func artwork(from record: WaltersRecord) -> Artwork? {
        guard let imageURL = URL(string: record.imageURL) else { return nil }

        return Artwork(
            id:         "walters-\(record.id)",
            imageURL:   imageURL,
            title:      record.title.isEmpty ? "Untitled" : record.title,
            artistName: record.artist.isEmpty ? "Unknown Artist" : record.artist,
            date:       record.date,
            credit:     "The Walters Art Museum",
            museumURL:  URL(string: "https://art.thewalters.org/object/\(record.id)/")
        )
    }
}
