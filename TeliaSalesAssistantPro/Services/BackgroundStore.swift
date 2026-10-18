import SwiftUI
import UIKit
import TeliaCore

// MARK: - Background photo storage (local only)

/// Imports photos from the native PhotosPicker (no library permission) and
/// stores a downscaled copy in the app's own Documents directory. Nothing is
/// ever uploaded; the original stays in the user's photo library untouched.
///
/// DS 2.2 (Update 1.3): decoded images are cached (`NSCache`) and decoded
/// exactly once per file — previously the background layer re-read the JPEG
/// from disk on every root-view render, which caused main-thread jank and
/// memory churn whenever the user navigated.
enum BackgroundStore {

    /// Cache of decoded, screen-ready background images.
    private static let imageCache = NSCache<NSString, UIImage>()

    static var backgroundsDirectory: URL {
        let dir = DataStore.baseURL.appendingPathComponent("Backgrounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Downscales and saves the picked image. Returns the stored file name.
    /// The file is written *before* any preference is changed, so a failed
    /// import can never leave the app without its active background.
    static func importPhoto(_ data: Data) throws -> String {
        guard let image = UIImage(data: data) else {
            throw BackgroundImportError.notAnImage
        }
        // Bound the size: a background never needs more than ~1600 px on the
        // long edge, which keeps memory and disk usage modest on old devices.
        let maxEdge: CGFloat = 1600
        var target = image
        let longEdge = max(image.size.width, image.size.height)
        if longEdge > maxEdge {
            let scale = maxEdge / longEdge
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            target = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }
        guard let jpeg = target.jpegData(compressionQuality: 0.85) else {
            throw BackgroundImportError.encodingFailed
        }
        let fileName = "bg-\(UUID().uuidString).jpg"
        let url = backgroundsDirectory.appendingPathComponent(fileName)
        do {
            try jpeg.write(to: url, options: .atomic)
        } catch {
            throw BackgroundImportError.writeFailed(error.localizedDescription)
        }
        cache(image: target, fileName: fileName)
        return fileName
    }

    /// Loads a stored background photo — decoded once, then served from cache.
    /// Returns nil for missing/corrupt files so the UI falls back to the
    /// default background instead of crashing or showing a broken layer.
    static func loadPhoto(fileName: String) -> UIImage? {
        if let cached = imageCache.object(forKey: fileName as NSString) {
            return cached
        }
        let url = backgroundsDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        cache(image: image, fileName: fileName)
        return image
    }

    private static func cache(image: UIImage, fileName: String) {
        imageCache.setObject(image, forKey: fileName as NSString)
    }

    /// Deletes a stored photo. Called only *after* the preference no longer
    /// references the file, so the active background is never removed while
    /// still selected.
    static func deletePhoto(fileName: String) {
        let url = backgroundsDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
        imageCache.removeObject(forKey: fileName as NSString)
    }

    /// Removes the stored photo referenced by a preference, if any, without
    /// touching anything else.
    static func cleanUpPreference(_ preference: BackgroundPreference) {
        if preference.kind == .photo, let fileName = preference.fileName {
            deletePhoto(fileName: fileName)
        }
    }
}

// MARK: - Errors

enum BackgroundImportError: LocalizedError {
    case notAnImage
    case encodingFailed
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAnImage: return "Filen kunde inte läsas som en bild."
        case .encodingFailed: return "Bilden kunde inte sparas."
        case .writeFailed(let m): return "Kunde inte spara bakgrunden: \(m)"
        }
    }
}
