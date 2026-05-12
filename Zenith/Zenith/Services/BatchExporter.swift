//
//  BatchExporter.swift
//  Zenith
//

import AppKit
import ImageIO
import UniformTypeIdentifiers

enum BatchExportFormat: String, CaseIterable, Identifiable {
    case jpeg
    case png
    case tiff

    var id: String { rawValue }

    var utType: UTType {
        switch self {
        case .jpeg: .jpeg
        case .png: .png
        case .tiff: .tiff
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .tiff: "tif"
        }
    }
}

enum BatchExporterError: LocalizedError {
    case couldNotCreateDestination
    case renderFailed
    case noPhotos

    var errorDescription: String? {
        switch self {
        case .couldNotCreateDestination:
            return String(localized: "batch.export.error.destination")
        case .renderFailed:
            return String(localized: "batch.export.error.render")
        case .noPhotos:
            return String(localized: "batch.export.error.no_photos")
        }
    }
}

/// Exporte de manière asynchrone une sélection de photos avec rendu développé.
/// L'API rapporte la progression via `onProgress` (0…1) après chaque photo et cède le main actor entre fichiers.
@MainActor
enum BatchExporter {
    static func export(
        photos: [PhotoRecord],
        to destinationDirectory: URL,
        format: BatchExportFormat,
        quality: CGFloat = 0.92,
        onProgress: @MainActor (Double) -> Void = { _ in }
    ) async throws {
        guard !photos.isEmpty else { throw BatchExporterError.noPhotos }

        let destAccess = destinationDirectory.startAccessingSecurityScopedResource()
        defer { if destAccess { destinationDirectory.stopAccessingSecurityScopedResource() } }

        let total = photos.count
        onProgress(0)

        for (idx, photo) in photos.enumerated() {
            try Task.checkCancellation()

            try await exportSingle(
                photo: photo,
                to: destinationDirectory,
                format: format,
                quality: quality
            )

            let progress = Double(idx + 1) / Double(total)
            onProgress(progress)
            await Task.yield()
        }
    }

    private static func exportSingle(
        photo: PhotoRecord,
        to destinationDirectory: URL,
        format: BatchExportFormat,
        quality: CGFloat
    ) async throws {
        let url = try photo.resolvedURL()
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }

        guard let rendered = DevelopPreviewRenderer.renderForExport(url: url, settings: photo.developSettings),
              let tiff = rendered.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cgImage = rep.cgImage
        else {
            throw BatchExporterError.renderFailed
        }

        let baseName = (photo.filename as NSString).deletingPathExtension
        let uniqueBase = "\(baseName)-\(String(photo.id.uuidString.prefix(8)))"
        let outURL = destinationDirectory
            .appendingPathComponent(uniqueBase)
            .appendingPathExtension(format.fileExtension)

        guard let dest = CGImageDestinationCreateWithURL(
            outURL as CFURL,
            format.utType.identifier as CFString,
            1,
            nil
        ) else {
            throw BatchExporterError.couldNotCreateDestination
        }

        var props: [CFString: Any] = [:]
        if format == .jpeg {
            props[kCGImageDestinationLossyCompressionQuality] = quality
        }

        CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw BatchExporterError.couldNotCreateDestination
        }
    }
}
