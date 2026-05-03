//
//  PhotoImporter.swift
//  Zenith
//

import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum PhotoImporterError: LocalizedError {
    case catalogLimitReached(Int)
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .catalogLimitReached(let max):
            return String(format: String(localized: "import.error.limit_format"), max)
        case .importFailed(let reason):
            return reason
        }
    }
}

@MainActor
enum PhotoImporter {
    static let maxPhotos = 40_000

    static func importPhotos(modelContext: ModelContext, collectionID: UUID?, currentCount: Int) throws {
        guard currentCount < maxPhotos else {
            throw PhotoImporterError.catalogLimitReached(maxPhotos)
        }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = String(localized: "import.message")
        var types: [UTType] = [.image, .rawImage, .jpeg, .png, .tiff, .heif]
        if let psd = UTType(filenameExtension: "psd") { types.append(psd) }
        let rawExtensions = ["nef", "cr2", "cr3", "arw", "dng", "orf", "rw2", "raf"]
        for ext in rawExtensions {
            if let t = UTType(filenameExtension: ext) {
                types.append(t)
            }
        }
        panel.allowedContentTypes = types

        guard panel.runModal() == .OK else { return }

        var remaining = maxPhotos - currentCount
        for url in panel.urls {
            guard remaining > 0 else { break }
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let bookmark = try SecurityScoped.bookmark(for: url)
                let dims = ThumbnailLoader.pixelSize(of: url)
                let photo = PhotoRecord(
                    fileBookmark: bookmark,
                    filename: url.lastPathComponent,
                    collectionID: collectionID,
                    pixelWidth: dims.0,
                    pixelHeight: dims.1
                )
                modelContext.insert(photo)
                remaining -= 1
            } catch {
                throw PhotoImporterError.importFailed(error.localizedDescription)
            }
        }
        try modelContext.save()
    }
}
