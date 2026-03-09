import Foundation

actor ArtInstituteService {
    static let shared = ArtInstituteService()

    private let searchURL = URL(string: "https://api.artic.edu/api/v1/artworks/search")!
    private let session   = URLSession.shared
    private let imageBase = "https://www.artic.edu/iiif/2"

    // Cached after the first probe so subsequent calls make only one request.
    private var cachedTotalItems: Int?

    // MARK: - API Response Types

    private struct SearchResponse: Decodable {
        let pagination: Pagination
        let data: [AICObject]
    }

    private struct Pagination: Decodable {
        let total: Int
        let totalPages: Int
        enum CodingKeys: String, CodingKey {
            case total
            case totalPages = "total_pages"
        }
    }

    private struct AICObject: Decodable {
        let id: Int
        let title: String?
        let artistDisplay: String?
        let dateDisplay: String?
        let imageId: String?

        enum CodingKeys: String, CodingKey {
            case id
            case title
            case artistDisplay = "artist_display"
            case dateDisplay   = "date_display"
            case imageId       = "image_id"
        }
    }

    // MARK: - Public API

    /// Fetches a random selection of public-domain paintings from the AIC collection.
    /// No dimension filter is applied — AIC's collection skews portrait, which
    /// displays well in a portrait card without any special handling.
    func fetchRandomPaintings(count: Int = 10) async throws -> [Artwork] {
        // Probe on first call to learn how many paintings exist, then cache the
        // count so every subsequent call only needs a single network request.
        if cachedTotalItems == nil {
            let probe = try await post(page: 1, limit: 1)
            cachedTotalItems = probe.pagination.total
        }

        // Elasticsearch caps search results at 10,000; at 100/page that is 100 pages.
        let pageCount = max(1, min((cachedTotalItems! + 99) / 100, 10))
        let page = Int.random(in: 1...pageCount)

        let response = try await post(page: page, limit: 100)
        return response.data
            .filter { $0.imageId != nil }
            .shuffled()
            .prefix(count)
            .compactMap(artwork(from:))
    }

    // MARK: - Private

    private func post(page: Int, limit: Int) async throws -> SearchResponse {
        let body: [String: Any] = [
            "query": [
                "bool": [
                    "filter": [
                        ["term": ["is_public_domain": true]],
                        ["term": ["artwork_type_id": 1]],
                    ]
                ]
            ],
            "fields": "id,title,artist_display,date_display,image_id",
            "limit": limit,
            "page":  page,
        ]

        var request = URLRequest(url: searchURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: request)
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return decoded
    }

    private func artwork(from obj: AICObject) -> Artwork? {
        guard let imageId = obj.imageId,
              let imageURL = URL(string: "\(imageBase)/\(imageId)/full/843,/0/default.jpg")
        else { return nil }

        // artist_display appends nationality and dates on subsequent lines;
        // e.g. "Georges Seurat\nFrench, 1859–1891" — keep only the name.
        let artist = obj.artistDisplay?
            .components(separatedBy: "\n")
            .first?
            .trimmingCharacters(in: .whitespaces) ?? ""

        return Artwork(
            id:         "aic-\(obj.id)",
            imageURL:   imageURL,
            title:      (obj.title ?? "").isEmpty ? "Untitled" : obj.title ?? "Untitled",
            artistName: artist.isEmpty ? "Unknown Artist" : artist,
            date:       obj.dateDisplay ?? "",
            credit:     "Art Institute of Chicago"
        )
    }
}
