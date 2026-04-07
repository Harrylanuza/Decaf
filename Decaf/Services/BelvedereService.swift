import Foundation

/// Serves public-domain paintings from the Belvedere museum, Vienna.
///
/// The Belvedere does not provide a REST search API. All access is through
/// their IIIF Presentation API v2, which requires no API key:
///   https://sammlung.belvedere.at/apis/iiif/presentation/v2/
///
/// Collection listing (100 manifests per page, 57 pages for paintings):
///   https://sammlung.belvedere.at/apis/iiif/presentation/v2/collection/module/objects
///     ?filter=classifications_en%3APainting&page={n}
///
/// Individual manifest:
///   https://sammlung.belvedere.at/apis/iiif/presentation/v2/1-objects-{id}/manifest
///
/// CC0 check: manifest `attribution` == the literal string "null".
/// Copyrighted works carry "© {rights holder}" instead.
///
/// All metadata (title, artist, date) is packed into a single comma-delimited
/// canvas label string — the `metadata` array is always empty:
///   "Artist, Title, Year, Medium, Dimensions, Belvedere, Wien, Inv.-Nr. X"
///
/// Images are served via IIIF Image API v2 at no cost:
///   https://sammlung.belvedere.at/apis/iiif/image/v2/{imageID}/full/843,/0/default.jpg
///
/// Canvas width/height are embedded in each manifest, so aspect-ratio filtering
/// requires no separate info.json probe.
///
/// The usable pool is ~3,512 CC0 paintings out of 5,658 total.
actor BelvedereService {
    static let shared = BelvedereService()

    private let session = URLSession.shared

    private static let collectionBase =
        "https://sammlung.belvedere.at/apis/iiif/presentation/v2/collection/module/objects"

    // Painting manifest URLs harvested from the collection listing.
    // nil until the background harvest completes.
    private var manifestURLs: [URL]? = nil
    // Non-nil once a harvest has been started, preventing a double-start.
    private var harvestTask: Task<Void, Never>? = nil

    // MARK: - API Response Types

    private struct CollectionPage: Decodable {
        let total: Int?
        let manifests: [ManifestRef]?

        struct ManifestRef: Decodable {
            let id: String
            enum CodingKeys: String, CodingKey { case id = "@id" }
        }
    }

    private struct Manifest: Decodable {
        let attribution: String?
        let sequences: [Sequence]

        struct Sequence: Decodable {
            let canvases: [Canvas]
        }

        struct Canvas: Decodable {
            let label: String?
            let width: Int?
            let height: Int?
            let images: [CanvasImage]

            struct CanvasImage: Decodable {
                let resource: Resource

                struct Resource: Decodable {
                    let service: Service?

                    struct Service: Decodable {
                        let id: String
                        enum CodingKeys: String, CodingKey { case id = "@id" }
                    }
                }
            }
        }
    }

    // MARK: - Public API

    /// Fetches a random selection of CC0 Belvedere paintings.
    ///
    /// On first call the background harvest starts (57 collection-page requests).
    /// While it runs, a single random collection page is used as a fallback so
    /// the feed is never blocked. Once the harvest completes, calls sample
    /// uniformly from the full ~5,658-URL pool.
    func fetchRandomPaintings(count: Int = 10) async throws -> [Artwork] {
        startHarvestIfNeeded()

        let urls: [URL]
        if let pool = manifestURLs {
            // Harvest complete — shuffle and take a generous batch.
            // Multiplier of 6 accounts for ~38% non-CC0 rejection and ~15%
            // aspect-ratio rejection, leaving a comfortable margin.
            urls = Array(pool.shuffled().prefix(count * 6))
        } else {
            // Harvest still in progress — fall back to a random collection page.
            urls = try await fetchRandomPageURLs()
        }

        return await withTaskGroup(of: Artwork?.self) { group in
            for url in urls {
                group.addTask { try? await self.fetchArtwork(from: url) }
            }
            var results: [Artwork] = []
            for await artwork in group {
                if let artwork { results.append(artwork) }
                if results.count >= count {
                    group.cancelAll()
                    break
                }
            }
            return Array(results.prefix(count))
        }
    }

    // MARK: - Background Harvest

    private func startHarvestIfNeeded() {
        guard harvestTask == nil else { return }
        harvestTask = Task { await performHarvest() }
    }

    /// Walks all painting collection pages and accumulates manifest URLs.
    /// Runs entirely in the background; each `await session.data(from:)` yields
    /// the actor executor so concurrent `fetchRandomPaintings` callers are never
    /// blocked.
    private func performHarvest() async {
        var allURLs: [URL] = []

        guard let firstPage = try? await fetchCollectionPage(page: 1),
              let total = firstPage.total, total > 0
        else { return }

        for ref in firstPage.manifests ?? [] {
            if let url = URL(string: ref.id) { allURLs.append(url) }
        }

        let pageCount = (total + 99) / 100
        guard pageCount > 1 else {
            manifestURLs = allURLs
            return
        }

        for page in 2...pageCount {
            guard let pageData = try? await fetchCollectionPage(page: page) else { continue }
            for ref in pageData.manifests ?? [] {
                if let url = URL(string: ref.id) { allURLs.append(url) }
            }
        }

        manifestURLs = allURLs
    }

    // MARK: - Private Helpers

    private func fetchCollectionPage(page: Int) async throws -> CollectionPage {
        guard var components = URLComponents(string: BelvedereService.collectionBase)
        else { throw URLError(.badURL) }
        components.queryItems = [
            URLQueryItem(name: "filter", value: "classifications_en:Painting"),
            URLQueryItem(name: "page",   value: String(page)),
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(CollectionPage.self, from: data)
    }

    /// Returns manifest URLs from a random painting collection page.
    /// Used as a fallback while the background harvest is still running.
    private func fetchRandomPageURLs() async throws -> [URL] {
        let page = Int.random(in: 1...57)
        let pageData = try await fetchCollectionPage(page: page)
        return (pageData.manifests ?? [])
            .compactMap { URL(string: $0.id) }
            .shuffled()
    }

    /// Fetches a manifest, checks CC0 status, applies aspect-ratio filter,
    /// and maps to an Artwork. Returns nil for any rejected record.
    private func fetchArtwork(from manifestURL: URL) async throws -> Artwork? {
        let (data, _) = try await session.data(from: manifestURL)
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)

        // Skip anything that isn't explicitly marked CC0.
        guard manifest.attribution == "null" else { return nil }

        guard let canvas  = manifest.sequences.first?.canvases.first,
              let width   = canvas.width, let height = canvas.height, width > 0, height > 0,
              let imageServiceID = canvas.images.first?.resource.service?.id
        else { return nil }

        // Portrait-friendly aspect-ratio filter (same bounds as all other services).
        let ratio     = Double(width) / Double(height)
        let shortSide = min(width, height)
        guard ratio >= 0.4, ratio <= 2.0, shortSide >= 400 else { return nil }

        let label = canvas.label ?? ""

        // Reject Artothek des Bundes loans — these are works the Belvedere does not
        // own or license; their CC0 attribution field is unreliable for such items.
        guard !label.contains("Artothek") else { return nil }

        let (artist, title, date) = parseCanvasLabel(label)

        // Reject works created in 1926 or later. The Belvedere incorrectly emits
        // attribution == "null" for some in-copyright works (e.g. living artists,
        // incomplete metadata). Under EU life+70 copyright, works from 1926 onward
        // carry meaningful risk; the Belvedere's historic core is pre-1920 anyway.
        if let year = Int(date.prefix(4)), year >= 1926 { return nil }

        // Object ID: the path component before "/manifest", e.g. "1-objects-395".
        let objectID = manifestURL.deletingLastPathComponent().lastPathComponent

        guard let imageURL = URL(string: "\(imageServiceID)/full/843,/0/default.jpg")
        else { return nil }

        return Artwork(
            id:         "belvedere-\(objectID)",
            imageURL:   imageURL,
            title:      title.isEmpty    ? "Untitled"       : title,
            artistName: artist.isEmpty   ? "Unknown Artist" : artist,
            date:       date,
            credit:     "Belvedere, Vienna",
            museumURL:  URL(string: "https://sammlung.belvedere.at/objects/\(objectID.components(separatedBy: "-").last ?? objectID)")
        )
    }

    /// Parses the Belvedere canvas label format:
    ///   "Artist, Title, Year, Medium, Dimensions, Belvedere, Wien, Inv.-Nr. X"
    ///
    /// Strategy: the first component is always the artist; the first component
    /// that starts with four digits is the year; everything between the artist
    /// and the year (joined back with ", ") is the title.
    private func parseCanvasLabel(_ label: String) -> (artist: String, title: String, date: String) {
        let parts = label.components(separatedBy: ", ")
        guard parts.count >= 2 else { return (label, "", "") }

        let artist = parts[0]

        // Find the first component whose leading four characters are all digits.
        if let yearIndex = parts.indices.first(where: {
            $0 > 0 &&
            parts[$0].count >= 4 &&
            parts[$0].prefix(4).allSatisfy(\.isNumber)
        }) {
            let title = yearIndex > 1
                ? parts[1..<yearIndex].joined(separator: ", ")
                : ""
            return (artist, title, parts[yearIndex])
        }

        // No year found — treat second component as title.
        return (artist, parts[1], "")
    }
}
