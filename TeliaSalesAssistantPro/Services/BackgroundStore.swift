import SwiftUI
import UIKit
import TeliaCore

// MARK: - Background photo storage (local only)

/// Imports photos from the native PhotosPicker (no library permission) and
/// stores a downscaled copy in the app's Documents directory. Nothing is ever
/// uploaded; the original stays in the user's photo library untouched.
enum BackgroundStore {

    static var backgroundsDirectory: URL {
        let dir = DataStore.baseURL.appendingPathComponent("Backgrounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Downscales and saves the picked image. Returns the stored file name.
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
        return fileName
    }

    /// Loads a stored background photo. Returns nil for missing/corrupt files
    /// so the UI can fall back to the default background instead.
    static func loadPhoto(fileName: String) -> UIImage? {
        let url = backgroundsDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Deletes a stored photo (used when the user resets or replaces it).
    static func deletePhoto(fileName: String) {
        let url = backgroundsDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
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
