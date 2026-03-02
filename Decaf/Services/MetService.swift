import Foundation

actor MetService {
    static let shared = MetService()

    private let baseURL = URL(string: "https://collectionapi.metmuseum.org/public/collection/v1")!
    private let session = URLSession.shared

    // MARK: - API Response Types

    private struct SearchResponse: Decodable {
        let total: Int
        let objectIDs: [Int]?
    }

    private struct MetObject: Decodable {
        let objectID: Int
        let title: String
        let artistDisplayName: String
        let objectDate: String
        let primaryImage: String
        let primaryImageSmall: String
        let isPublicDomain: Bool
        let repository: String
        let medium: String
    }

    // Departments to source from.
    private let departmentIDs = [1, 11]  // 1 = American Wing, 11 = European Paintings

    // Medium substrings that identify painted works (case-insensitive).
    private let paintingMedia = ["oil on canvas", "oil on panel", "tempera"]

    // MARK: - Public API

    /// Fetches a random selection of public-domain artworks with images.
    func fetchRandomArtworks(count: Int = 20) async throws -> [Artwork] {
        let ids = try await fetchCandidateIDs()
        guard !ids.isEmpty else { return [] }
        return await fetchSample(from: ids, count: count)
    }

    // MARK: - Private

    /// Returns object IDs from the target departments that have images.
    /// Public-domain filtering is applied per-object in `fetchArtwork`.
    private func fetchCandidateIDs() async throws -> [Int] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("objects"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "departmentIds", value: departmentIDs.map(String.init).joined(separator: "|")),
            URLQueryItem(name: "hasImages",     value: "true"),
        ]

        let (data, _) = try await session.data(from: components.url!)
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        return response.objectIDs ?? []
    }

    /// Concurrently fetches object details, stopping once `count` valid artworks are collected.
    private func fetchSample(from ids: [Int], count: Int) async -> [Artwork] {
        // Fetch extra candidates: American Wing contains many non-painting objects,
        // so the medium filter will reject a large portion of them.
        let candidates = ids.shuffled().prefix(count * 8)

        return await withTaskGroup(of: Artwork?.self) { group in
            for id in candidates {
                group.addTask { try? await self.fetchArtwork(id: id) }
            }

            var results: [Artwork] = []
            for await artwork in group {
                if let artwork {
                    results.append(artwork)
                }
                if results.count >= count {
                    group.cancelAll()
                    break
                }
            }
            return Array(results.prefix(count))
        }
    }

    private func fetchArtwork(id: Int) async throws -> Artwork? {
        let url = baseURL.appendingPathComponent("objects/\(id)")
        let (data, _) = try await session.data(from: url)
        let obj = try JSONDecoder().decode(MetObject.self, from: data)

        let rawImage = obj.primaryImageSmall.isEmpty ? obj.primaryImage : obj.primaryImageSmall
        let mediumLowered = obj.medium.lowercased()
        guard obj.isPublicDomain,
              !rawImage.isEmpty,
              let imageURL = URL(string: rawImage),
              paintingMedia.contains(where: { mediumLowered.contains($0) }) else {
            return nil
        }

        return Artwork(
            id: String(obj.objectID),
            imageURL: imageURL,
            title: obj.title.isEmpty ? "Untitled" : obj.title,
            artistName: obj.artistDisplayName.isEmpty ? "Unknown Artist" : obj.artistDisplayName,
            date: obj.objectDate,
            credit: obj.repository.isEmpty ? "The Metropolitan Museum of Art" : obj.repository
        )
    }
}
