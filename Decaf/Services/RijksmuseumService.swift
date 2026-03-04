import Foundation

actor RijksmuseumService {
    static let shared = RijksmuseumService()

    private let baseURL = URL(string: "https://data.rijksmuseum.nl/oai")!
    private let session = URLSession.shared

    // Painting-focused OAI-PMH sets. One is chosen randomly each session
    // so the feed draws from different slices of the collection over time.
    private let paintingSets = [
        "261208",   // Schilderijen — general paintings
        "26121",    // Dutch Paintings of the Seventeenth Century
        "26118",    // Flemish Paintings
        "2616",     // Early Netherlandish Paintings
    ]

    // MARK: - Public API

    /// Fetches a random selection of public-domain paintings with images,
    /// silently omitting any whose dimensions are too extreme to display well
    /// in a full-screen portrait card (panoramics, narrow columns, tiny images).
    func fetchRandomPaintings(count: Int = 10) async throws -> [Artwork] {
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
        let records = OAIParser.parse(data)

        // Pull more candidates than needed so filtering still yields enough.
        let candidates = records
            .filter { $0.hasImage && $0.isPublicDomain }
            .shuffled()
            .prefix(count * 4)

        return await withTaskGroup(of: Artwork?.self) { group in
            for record in candidates {
                group.addTask {
                    guard let imageURL = record.imageURL else { return nil }
                    // Lightweight IIIF info.json probe — no image download.
                    guard let dims = await iiifImageDimensions(imageURL: imageURL),
                          dims.isSuitable else { return nil }
                    return Artwork(
                        id: record.catalogNumber.isEmpty ? record.lodIdentifier : record.catalogNumber,
                        imageURL: imageURL,
                        title: record.title.isEmpty ? "Untitled" : record.title,
                        artistName: record.creator.isEmpty ? "Unknown Artist" : record.creator,
                        date: record.date,
                        credit: "Rijksmuseum, Amsterdam"
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
        rights.contains("publicdomain") || rights.contains("creativecommons")
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
    private var current = OAIRecord()
    private var inHeader = false
    private var inMetadata = false
    private var currentText = ""

    static func parse(_ data: Data) -> [OAIRecord] {
        let parser = OAIParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.parse()
        return parser.records
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

        default:
            break
        }

        currentText = ""
    }
}
