import UIKit

/// Manages locally-cached copies of saved artwork images.
///
/// Images are stored as JPEG files under
/// `Application Support/SavedImages/<sanitised-artworkID>.jpg`.
/// Using Application Support (rather than Caches) ensures iOS does not
/// evict the files under storage pressure — the user's saved collection
/// must remain intact offline.
struct ImageStore {

    // MARK: - Paths

    private static let subdirectory = "SavedImages"

    /// The directory that holds all saved images, created on first access.
    private static var directory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(subdirectory)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir
    }

    /// Sanitises an artwork ID into a filesystem-safe filename stem.
    private static func stem(for artworkID: String) -> String {
        artworkID
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    /// The relative path (from Application Support) stored in `FavoriteItem`.
    /// Using a relative path keeps saved items portable across OS-level moves
    /// of the Application Support directory.
    static func relativePath(for artworkID: String) -> String {
        "\(subdirectory)/\(stem(for: artworkID)).jpg"
    }

    /// Resolves a stored relative path to an absolute `file://` URL.
    /// Returns `nil` if the file does not exist on disk.
    static func fileURL(for relativePath: String) -> URL? {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Operations

    /// Downloads the image at `remoteURL`, re-encodes it as JPEG, and writes
    /// it to disk.  Returns the relative path on success so it can be stored
    /// in `FavoriteItem.localImagePath`.
    @discardableResult
    static func save(imageAt remoteURL: URL, artworkID: String) async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: remoteURL)

        // Re-encode as JPEG to normalise format and keep file sizes manageable.
        guard let image    = UIImage(data: data),
              let jpegData = image.jpegData(compressionQuality: 0.85)
        else { throw CocoaError(.fileWriteUnknown) }

        let fileURL = directory.appendingPathComponent("\(stem(for: artworkID)).jpg")
        try jpegData.write(to: fileURL, options: .atomic)
        return relativePath(for: artworkID)
    }

    /// Removes the locally stored image for `artworkID`.
    /// Silently ignores errors (file may already have been deleted).
    static func delete(for artworkID: String) {
        let fileURL = directory.appendingPathComponent("\(stem(for: artworkID)).jpg")
        try? FileManager.default.removeItem(at: fileURL)
    }
}
