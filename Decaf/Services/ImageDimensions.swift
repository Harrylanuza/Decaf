import Foundation

/// Native pixel dimensions of an image and whether they are suitable
/// for display in a full-screen portrait card.
struct ImageDimensions {
    let width: Int
    let height: Int

    /// Returns false for images that would look bad after scaledToFit clipping
    /// in a portrait card (~390 × 600 pt on a typical iPhone):
    ///
    /// - Panoramics (width/height > 2.0): only a thin horizontal strip visible.
    /// - Narrow columns (width/height < 0.4): only a thin vertical strip visible.
    /// - Tiny images (shortest side < 400 px): would look pixelated at card size.
    var isSuitable: Bool {
        let ratio = Double(width) / Double(height)
        return ratio >= 0.4 && ratio <= 2.0 && min(width, height) >= 400
    }
}

/// Fetches the native pixel dimensions of a IIIF-served image without
/// downloading the image itself.
///
/// IIIF Image API URL structure:
///   {scheme}://{host}/{prefix}/{identifier}/{region}/{size}/{rotation}/{quality}.{format}
///
/// Removing the last 4 path components reaches the identifier base;
/// appending `/info.json` returns a small JSON document containing
/// the master `width` and `height` of the image.
func iiifImageDimensions(imageURL: URL) async -> ImageDimensions? {
    var base = imageURL
    for _ in 0..<4 { base = base.deletingLastPathComponent() }
    let infoURL = base.appendingPathComponent("info.json")

    guard let (data, _) = try? await URLSession.shared.data(from: infoURL) else { return nil }

    struct IIIFInfo: Decodable { let width, height: Int }
    guard let info = try? JSONDecoder().decode(IIIFInfo.self, from: data) else { return nil }
    return ImageDimensions(width: info.width, height: info.height)
}
