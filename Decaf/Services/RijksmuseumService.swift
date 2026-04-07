import Foundation

actor RijksmuseumService {
    static let shared = RijksmuseumService()

    private let baseURL = URL(string: "https://data.rijksmuseum.nl/oai")!
    private let session = URLSession.shared

    // Painting-focused OAI-PMH sets harvested in full each session.
    private let paintingSets = [
        "261208",   // Schilderijen — general paintings (~4 900 records)
        "26121",    // Dutch Paintings of the Seventeenth Century (~720 records)
        "26118",    // Flemish Paintings (~130 records)
        "2616",     // Early Netherlandish Paintings (~160 records)
    ]

    // Full record pool built by the background harvest. nil until complete.
    private var harvestedRecords: [OAIRecord]? = nil
    // Non-nil once the harvest has been started, preventing a double-start.
    private var harvestTask: Task<Void, Never>? = nil

    // MARK: - Public API

    /// Fetches a random selection of public-domain paintings with images,
    /// silently omitting any whose dimensions are too extreme to display well
    /// in a full-screen portrait card (panoramics, narrow columns, tiny images).
    ///
    /// On the first call the background harvest is started. While it is still
    /// running a single-page fallback (the original behaviour) is used so the
    /// feed is never blocked. Once the harvest completes, subsequent calls
    /// sample randomly from the full ~5 900-record pool.
    func fetchRandomPaintings(count: Int = 10) async throws -> [Artwork] {
        // Kick off the background harvest on first call if not already running.
        startHarvestIfNeeded()

        // Build the candidate list — full pool when ready, single page otherwise.
        let candidates: [OAIRecord]

        if let pool = harvestedRecords {
            // Harvest complete: sample uniformly from the entire collection.
            candidates = Array(
                pool
                    .filter { $0.hasImage && $0.isPublicDomain }
                    .shuffled()
                    .prefix(count * 4)
            )
        } else {
            // Harvest still in progress — fall back to a single-page fetch.
            guard let set = paintingSets.randomElement() else { return [] }

            guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
            else { throw URLError(.badURL) }

            components.queryItems = [
                URLQueryItem(name: "verb",           value: "ListRecords"),
                URLQueryItem(name: "metadataPrefix", value: "oai_dc"),
                URLQueryItem(name: "set",            value: set),
            ]

            guard let url = components.url else { throw URLError(.badURL) }
            let (data, _) = try await session.data(from: url)
            let (records, _) = OAIParser.parse(data)
            candidates = Array(
                records
                    .filter { $0.hasImage && $0.isPublicDomain }
                    .shuffled()
                    .prefix(count * 4)
            )
        }

        // Pull more candidates than needed so filtering still yields enough.
        return await withTaskGroup(of: Artwork?.self) { group in
            for record in candidates {
                group.addTask {
                    guard let imageURL = record.imageURL else { return nil }
                    // Lightweight IIIF info.json probe — no image download.
                    guard let dims = await iiifImageDimensions(imageURL: imageURL),
                          dims.isSuitable else { return nil }
                    let artworkID = record.catalogNumber.isEmpty ? record.lodIdentifier : record.catalogNumber
                    return Artwork(
                        id:         artworkID,
                        imageURL:   imageURL,
                        title:      record.title.isEmpty ? "Untitled" : record.title,
                        artistName: record.creator.isEmpty ? "Unknown Artist" : record.creator,
                        date:       record.date,
                        credit:     "Rijksmuseum, Amsterdam",
                        museumURL:  URL(string: "https://www.rijksmuseum.nl/en/collection/\(artworkID)")
                    )
                }
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

    /// Starts the full-collection harvest if it has not already been started.
    /// Safe to call multiple times — only the first call has any effect.
    private func startHarvestIfNeeded() {
        guard harvestTask == nil else { return }
        harvestTask = Task { await performHarvest() }
    }

    /// Walks the complete OAI-PMH token chain for every set, accumulating all
    /// records into `harvestedRecords`. Runs entirely in the background; each
    /// `await session.data(from:)` suspends and yields the actor executor so
    /// concurrent callers of `fetchRandomPaintings` are never blocked.
    ///
    /// A network error on any single page breaks out of that set's loop but
    /// the harvest continues with the remaining sets.
    private func performHarvest() async {
        var allRecords: [OAIRecord] = []
        var seen = Set<String>()   // deduplicates across overlapping sets

        for set in paintingSets {
            // --- First page for this set ---
            guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
            else { continue }
            components.queryItems = [
                URLQueryItem(name: "verb",           value: "ListRecords"),
                URLQueryItem(name: "metadataPrefix", value: "oai_dc"),
                URLQueryItem(name: "set",            value: set),
            ]
            guard let url = components.url,
                  let (data, _) = try? await session.data(from: url)
            else { continue }

            let (firstRecords, firstToken) = OAIParser.parse(data)
            for r in firstRecords where !r.lodIdentifier.isEmpty {
                if seen.insert(r.lodIdentifier).inserted { allRecords.append(r) }
            }

            // --- Follow the token chain for remaining pages ---
            var currentToken = firstToken
            while let token = currentToken, !token.isEmpty {
                guard var tokenComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
                else { break }
                // OAI-PMH spec: resumptionToken requests must have ONLY verb + token.
                tokenComponents.queryItems = [
                    URLQueryItem(name: "verb",             value: "ListRecords"),
                    URLQueryItem(name: "resumptionToken",  value: token),
                ]
                guard let tokenURL = tokenComponents.url,
                      let (tokenData, _) = try? await session.data(from: tokenURL)
                else { break }

                let (moreRecords, nextToken) = OAIParser.parse(tokenData)
                for r in moreRecords where !r.lodIdentifier.isEmpty {
                    if seen.insert(r.lodIdentifier).inserted { allRecords.append(r) }
                }
                currentToken = nextToken
            }
        }

        harvestedRecords = allRecords
    }
}

// MARK: - OAI-PMH XML Parsing

private struct OAIRecord {
    var lodIdentifier: String = ""
    var catalogNumber: String = ""
    var title: String = ""
    var creator: String = ""
    var date: String = ""
    var imageURLString: String = ""
    var rights: String = ""

    var hasImage: Bool { !imageURLString.isEmpty }

    var isPublicDomain: Bool {
        // Only accept Public Domain Mark and CC0 — both contain "publicdomain"
        // in their URLs (creativecommons.org/publicdomain/mark/ and .../zero/).
        // The broader "creativecommons" check is removed because CC-BY, CC-SA,
        // and similar licensed works must not be redistributed without attribution.
        rights.contains("publicdomain")
    }

    var imageURL: URL? {
        // Cap width at 1200 px for efficient mobile loading.
        // dc:relation URLs use the IIIF pattern: /full/max/0/default.jpg
        let sized = imageURLString.replacingOccurrences(of: "/full/max/", with: "/full/1200,/")
        return URL(string: sized)
    }
}

private final class OAIParser: NSObject, XMLParserDelegate {
    private var records: [OAIRecord] = []
    private var resumptionToken: String? = nil
    private var current = OAIRecord()
    private var inHeader = false
    private var inMetadata = false
    private var currentText = ""

    /// Parses an OAI-PMH response and returns the records it contains together
    /// with the resumptionToken for the next page (nil when this is the last page).
    static func parse(_ data: Data) -> (records: [OAIRecord], resumptionToken: String?) {
        let parser = OAIParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.parse()
        return (parser.records, parser.resumptionToken)
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentText = ""
        switch elementName {
        case "record":
            current = OAIRecord()
            inHeader = false
            inMetadata = false
        case "header":
            inHeader = true
        case "metadata":
            inHeader = false
            inMetadata = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "header":
            inHeader = false

        case "identifier" where inHeader:
            current.lodIdentifier = text

        case "dc:identifier":
            // Catalog numbers look like "SK-C-5" or "SK-A-1490".
            // Skip plain http URIs that sometimes appear in this field.
            if !text.hasPrefix("http") { current.catalogNumber = text }

        case "dc:title":
            if current.title.isEmpty { current.title = text }

        case "dc:creator":
            // Take the first creator listed; subsequent ones are ignored.
            if current.creator.isEmpty { current.creator = text }

        case "dc:date":
            if current.date.isEmpty { current.date = text }

        case "dc:relation":
            // Image URL is delivered in dc:relation as a full IIIF path.
            if text.contains("iiif.micr.io") { current.imageURLString = text }

        case "dc:rights":
            current.rights = text

        case "record":
            records.append(current)

        case "resumptionToken":
            // An empty element signals the final page; a non-empty value is the
            // cursor token to pass as resumptionToken on the next request.
            resumptionToken = text.isEmpty ? nil : text

        default:
            break
        }

        currentText = ""
    }
}
