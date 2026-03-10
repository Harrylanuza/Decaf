import Foundation

/// Serves public-domain paintings from the Smithsonian American Art Museum.
///
/// The Smithsonian Open Access programme publishes CC0-licensed metadata as
/// line-delimited JSON on a public S3 bucket. Those files have been pre-processed
/// into `saam_paintings.json` (bundled with the app), which contains the 4 015
/// paintings that are:
///   - tagged objectType containing "paint" in the SAAM unit records
///   - carrying CC0 access on their online_media entry (idsId present)
///   - within the portrait-friendly aspect-ratio range (0.4–2.0) with a minimum
///     short side of 400 px (dimensions are available in the resources array so
///     no network probe is needed at runtime)
///
/// Images are served via the Smithsonian IDS endpoint — no API key required:
///   https://ids.si.edu/ids/download?id={idsId}_screen
///
/// The bundle JSON should be regenerated from the upstream S3 data when a new
/// app version is released to pick up newly open-accessed works.
struct SAAMService {
    static let shared = SAAMService()

    private static let imageBase = "https://ids.si.edu/ids/download?id="

    // MARK: - Bundle record type

    private struct SAAMRecord: Decodable {
        let id: String
        let title: String
        let artist: String
        let date: String
        let medium: String
        let idsId: String
    }

    // Full painting pool loaded once from the bundle — nil only if the JSON
    // is missing (should never happen in a correctly built app).
    private let pool: [SAAMRecord]

    private init() {
        guard let url     = Bundle.main.url(forResource: "saam_paintings", withExtension: "json"),
              let data    = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([SAAMRecord].self, from: data)
        else {
            pool = []
            return
        }
        pool = records
    }

    // MARK: - Public API

    /// Returns a random selection of public-domain SAAM paintings.
    /// Entirely synchronous — all metadata is in the bundle, no network calls needed.
    func fetchRandomPaintings(count: Int = 10) -> [Artwork] {
        pool
            .shuffled()
            .prefix(count)
            .compactMap(artwork(from:))
    }

    // MARK: - Private

    private func artwork(from record: SAAMRecord) -> Artwork? {
        guard let imageURL = URL(string: "\(SAAMService.imageBase)\(record.idsId)_screen")
        else { return nil }

        return Artwork(
            id:         "saam-\(record.id)",
            imageURL:   imageURL,
            title:      record.title.isEmpty ? "Untitled" : record.title,
            artistName: record.artist.isEmpty ? "Unknown Artist" : record.artist,
            date:       record.date,
            credit:     "Smithsonian Institution"
        )
    }
}
