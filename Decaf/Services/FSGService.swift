import Foundation

/// Serves public-domain paintings from the Freer Gallery of Art and
/// Arthur M. Sackler Gallery (Smithsonian Institution, Washington DC).
///
/// The Smithsonian Open Access programme publishes CC0-licensed metadata as
/// line-delimited JSON on a public S3 bucket. Those files have been pre-processed
/// into `fsg_paintings.json` (bundled with the app), which contains the 1 143
/// paintings that are:
///   - tagged objectType containing "paint" in the FSG unit records
///   - carrying CC0 access on their online_media entry (idsId present)
///   - within the portrait-friendly aspect-ratio range (0.4–2.0) with a minimum
///     short side of 400 px (dimensions are available in the resources array so
///     no network probe is needed at runtime; records without dimension data are
///     accepted as-is since they represent < 8 % of paintings)
///
/// The collection spans East Asian, South Asian, and Near Eastern art —
/// providing cultural diversity beyond the Western paintings in other sources.
///
/// Images are served via the Smithsonian IDS endpoint — no API key required:
///   https://ids.si.edu/ids/download?id={idsId}_screen
///
/// The bundle JSON should be regenerated from the upstream S3 data when a new
/// app version is released to pick up newly open-accessed works.
struct FSGService {
    static let shared = FSGService()

    private static let imageBase = "https://ids.si.edu/ids/download?id="

    // MARK: - Bundle record type

    private struct FSGRecord: Decodable {
        let id: String
        let title: String
        let artist: String
        let date: String
        let medium: String
        let idsId: String
        let pageURL: String?
    }

    // Full painting pool loaded once from the bundle — nil only if the JSON
    // is missing (should never happen in a correctly built app).
    private let pool: [FSGRecord]

    private init() {
        guard let url     = Bundle.main.url(forResource: "fsg_paintings", withExtension: "json"),
              let data    = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([FSGRecord].self, from: data)
        else {
            #if DEBUG
            print("⚠️ FSGService: failed to load fsg_paintings.json from bundle")
            #endif
            pool = []
            return
        }
        pool = records
    }

    // MARK: - Public API

    /// Returns a random selection of public-domain FSG paintings.
    /// Entirely synchronous — all metadata is in the bundle, no network calls needed.
    func fetchRandomPaintings(count: Int = 10) -> [Artwork] {
        pool
            .shuffled()
            .prefix(count)
            .compactMap(artwork(from:))
    }

    // MARK: - Private

    private func artwork(from record: FSGRecord) -> Artwork? {
        guard let imageURL = URL(string: "\(FSGService.imageBase)\(record.idsId)_screen")
        else { return nil }

        return Artwork(
            id:         "fsg-\(record.id)",
            imageURL:   imageURL,
            title:      record.title.isEmpty ? "Untitled" : record.title,
            artistName: record.artist.isEmpty ? "Unknown Artist" : record.artist,
            date:       record.date,
            credit:     "Smithsonian Institution",
            museumURL:  record.pageURL.flatMap(URL.init)
        )
    }
}
