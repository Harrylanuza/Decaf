import Foundation

/// Serves public-domain paintings from the Cleveland Museum of Art.
///
/// The CMA open-access REST API requires no API key and has no observed rate limits:
///   https://openaccess-api.clevelandart.org/api/artworks/
///
/// Every response includes pixel dimensions for each image variant, so no
/// separate IIIF info.json probe is required to apply the aspect-ratio filter.
///
/// Filtering applied at runtime:
///   - type=Painting, cc0=1, has_image=1  (server-side)
///   - technique does not contain "palm leaf" — excludes ~358 manuscript folios
///     that are tagged as paintings in the CMA data model
///   - aspect ratio 0.4–2.0, minimum short side 400 px  (using images.web dimensions)
///
/// Images are served from the CMA CDN — no API key required:
///   https://openaccess-cdn.clevelandart.org/{accession}/{accession}_web.jpg
actor ClevelandService {
    static let shared = ClevelandService()

    private let session = URLSession.shared
    private static let baseURL = "https://openaccess-api.clevelandart.org/api/artworks/"

    // Total CC0 painting count, cached after the first call so every subsequent
    // request makes only one network round-trip.
    private var cachedTotal: Int?

    // MARK: - API Response Types

    private struct ListResponse: Decodable {
        let info: Info
        let data: [CMAObject]

        struct Info: Decodable {
            let total: Int
        }
    }

    private struct CMAObject: Decodable {
        let id: Int
        let accession_number: String?
        let title: String?
        let creation_date: String?
        let technique: String?
        let creditline: String?
        let images: Images?
        let creators: [Creator]?

        struct Images: Decodable {
            let web: ImageVariant?
        }

        struct ImageVariant: Decodable {
            let url: String?
            let width: String?
            let height: String?
        }

        struct Creator: Decodable {
            let description: String?
            let role: String?
        }
    }

    // MARK: - Public API

    /// Fetches a random selection of public-domain CMA paintings.
    /// Caches the collection total after the first call; every subsequent
    /// call makes a single network request.
    func fetchRandomPaintings(count: Int = 10) async throws -> [Artwork] {
        if cachedTotal == nil {
            cachedTotal = try await fetchTotal()
        }
        let total = cachedTotal!
        // Fetch 3× candidates so the aspect-ratio and palm-leaf filters still
        // yield at least `count` artworks even with a ~30% rejection rate.
        let batchSize = count * 3
        let maxSkip = max(0, total - batchSize)
        let skip = Int.random(in: 0...maxSkip)

        let response = try await fetch(skip: skip, limit: batchSize)
        return response.data
            .compactMap(artwork(from:))
            .prefix(count)
            .map { $0 }
    }

    // MARK: - Private

    private func fetchTotal() async throws -> Int {
        let url = try buildURL(skip: 0, limit: 1)
        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(ListResponse.self, from: data)
        return response.info.total
    }

    private func fetch(skip: Int, limit: Int) async throws -> ListResponse {
        let url = try buildURL(skip: skip, limit: limit)
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(ListResponse.self, from: data)
    }

    private func buildURL(skip: Int, limit: Int) throws -> URL {
        guard var components = URLComponents(string: ClevelandService.baseURL)
        else { throw URLError(.badURL) }

        components.queryItems = [
            URLQueryItem(name: "type",      value: "Painting"),
            URLQueryItem(name: "cc0",       value: "1"),
            URLQueryItem(name: "has_image", value: "1"),
            URLQueryItem(name: "limit",     value: String(limit)),
            URLQueryItem(name: "skip",      value: String(skip)),
            URLQueryItem(name: "fields",    value: "id,accession_number,title,creation_date,technique,images,creators,creditline"),
        ]

        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }

    private func artwork(from obj: CMAObject) -> Artwork? {
        // Exclude manuscript content tagged as paintings in the CMA data model.
        //
        // Technique-based:
        //   "palm leaf" — manuscript folios written/painted on palm leaves
        //
        // Title-based (four groups identified by audit, ~1,217 records total):
        //   "tuti-nama"   — 654 Tuti-nama (Tales of a Parrot) illustrated folios
        //   starts "text," — 471 explicit text-side folios (Kalpa-sutra, Perfection
        //                     of Wisdom, etc.) whose title begins "Text, Folio …"
        //   "-sutra"/"sutra " — 47 illustrated folio sides from the same sutra
        //                       manuscripts, identified by the sutra name in the title
        //   "calligraphy" — 45 calligraphic text pages
        let tech  = obj.technique?.lowercased() ?? ""
        let title = obj.title?.lowercased() ?? ""
        guard !tech.contains("palm leaf"),
              !title.contains("tuti-nama"),
              !title.hasPrefix("text,"),
              !title.contains("-sutra"),
              !title.contains("sutra "),
              !title.contains("calligraphy")
        else { return nil }

        // Require a web image with valid pixel dimensions for aspect-ratio check.
        guard let web = obj.images?.web,
              let urlString = web.url, !urlString.isEmpty,
              let imageURL = URL(string: urlString),
              let wStr = web.width, let w = Int(wStr), w > 0,
              let hStr = web.height, let h = Int(hStr), h > 0
        else { return nil }

        // Portrait-friendly aspect-ratio filter (same bounds as NGA and SAAM).
        let ratio = Double(w) / Double(h)
        let shortSide = min(w, h)
        guard ratio >= 0.4, ratio <= 2.0, shortSide >= 400 else { return nil }

        // Artist name: strip the "(Nationality, dates)" suffix appended by CMA,
        // e.g. "John Singleton Copley (American, 1738–1815)" → "John Singleton Copley".
        let artist: String = {
            let desc = obj.creators?.first(where: { $0.role == "artist" })?.description
                    ?? obj.creators?.first?.description
            guard let raw = desc, !raw.isEmpty else { return "Unknown Artist" }
            return raw.components(separatedBy: " (").first
                      .map { $0.trimmingCharacters(in: .whitespaces) }
                   ?? raw
        }()

        let museumURL: URL? = obj.accession_number.flatMap {
            URL(string: "https://www.clevelandart.org/art/\($0)")
        }
        return Artwork(
            id:         "cma-\(obj.id)",
            imageURL:   imageURL,
            title:      (obj.title ?? "").isEmpty ? "Untitled" : obj.title!,
            artistName: artist.isEmpty ? "Unknown Artist" : artist,
            date:       obj.creation_date ?? "",
            credit:     "Cleveland Museum of Art",
            museumURL:  museumURL
        )
    }
}
