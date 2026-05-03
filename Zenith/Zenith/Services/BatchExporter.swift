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

    var errorDescription: String? {
        switch self {
        case .couldNotCreateDestination:
            return String(localized: "batch.export.error.destination")
        case .renderFailed:
            return String(localized: "batch.export.error.render")
        }
    }
}

@MainActor
enum BatchExporter {
    static func export(
        photos: [PhotoRecord],
        to destinationDirectory: URL,
        format: BatchExportFormat,
        quality: CGFloat = 0.92
    ) throws {
        let destAccess = destinationDirectory.startAccessingSecurityScopedResource()
        defer { if destAccess { destinationDirectory.stopAccessingSecurityScopedResource() } }

        for photo in photos {
            let url = try photo.resolvedURL()
            let started = url.startAccessingSecurityScopedResource()
            defer { if started { url.stopAccessingSecurityScopedResource() } }

            guard let rendered = DevelopPreviewRenderer.render(url: url, settings: photo.developSettings),
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
}
