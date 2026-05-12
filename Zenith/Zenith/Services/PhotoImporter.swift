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
    /// Aucune photo n’a pu être importée alors que des fichiers étaient sélectionnés.
    case allFilesFailed(failures: Int, firstReason: String)

    var errorDescription: String? {
        switch self {
        case .catalogLimitReached(let max):
            return String(format: String(localized: "import.error.limit_format"), max)
        case .importFailed(let reason):
            return reason
        case .allFilesFailed(let failures, let firstReason):
            let format = String(localized: "import.error.all_failed_format")
            return String(format: format, locale: .current, failures, firstReason)
        }
    }
}

/// Résumé d’une session d’import : combien de photos ont été insérées, combien ont échoué, première erreur rencontrée.
/// Permet de reporter à l’utilisateur ce qui s’est passé sans interrompre la boucle au premier raté.
struct PhotoImportSummary {
    var imported: Int = 0
    var skipped: Int = 0
    var failed: Int = 0
    var firstFailureReason: String?
}

@MainActor
enum PhotoImporter {
    static let maxPhotos = 40_000

    /// Extensions natives gérées (image standard + RAW les plus courants). Sert au filtrage du `NSOpenPanel`
    /// et à la validation des URL déposées par glisser/déposer.
    static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "jpe", "png", "tif", "tiff", "heic", "heif", "webp", "gif", "bmp", "psd",
        "nef", "cr2", "cr3", "arw", "dng", "orf", "rw2", "raf", "srw", "pef", "x3f"
    ]

    static var allowedContentTypes: [UTType] {
        var types: [UTType] = [.image, .rawImage, .jpeg, .png, .tiff, .heif]
        if let psd = UTType(filenameExtension: "psd") { types.append(psd) }
        for ext in ["nef", "cr2", "cr3", "arw", "dng", "orf", "rw2", "raf", "srw", "pef", "x3f"] {
            if let t = UTType(filenameExtension: ext) {
                types.append(t)
            }
        }
        return types
    }

    /// Ouvre un `NSOpenPanel` puis importe les fichiers choisis.
    @discardableResult
    static func importPhotos(modelContext: ModelContext, collectionID: UUID?, currentCount: Int) throws -> PhotoImportSummary {
        guard currentCount < maxPhotos else {
            throw PhotoImporterError.catalogLimitReached(maxPhotos)
        }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = String(localized: "import.message")
        panel.allowedContentTypes = allowedContentTypes

        guard panel.runModal() == .OK else { return PhotoImportSummary() }

        return try importPhotos(
            from: panel.urls,
            modelContext: modelContext,
            collectionID: collectionID,
            currentCount: currentCount,
            requireSecurityScope: true
        )
    }

    /// Variante pour les URL déjà disponibles (glisser/déposer Finder, intents, etc.).
    /// L’itération continue même si un fichier échoue : on accumule les erreurs au lieu d’interrompre tout l’import.
    @discardableResult
    static func importPhotos(
        from urls: [URL],
        modelContext: ModelContext,
        collectionID: UUID?,
        currentCount: Int,
        requireSecurityScope: Bool = false
    ) throws -> PhotoImportSummary {
        guard currentCount < maxPhotos else {
            throw PhotoImporterError.catalogLimitReached(maxPhotos)
        }

        let candidates = expandIntoSupportedFiles(urls)
        guard !candidates.isEmpty else { return PhotoImportSummary() }

        var summary = PhotoImportSummary()
        var remaining = maxPhotos - currentCount

        /// Sauvegarde par lots : on évite qu’une erreur tardive perde tous les inserts précédents.
        let batchSize = 50
        var pendingBatch = 0

        for url in candidates {
            guard remaining > 0 else {
                summary.skipped += 1
                continue
            }

            /// Pour les fichiers issus du `NSOpenPanel` ou d’un drag/drop, on doit prendre la portée de sécurité.
            /// `startAccessingSecurityScopedResource()` peut renvoyer `false` quand l’URL n’en a pas besoin (ex. fichiers locaux non sandboxés) :
            /// on tente quand même la lecture du bookmark.
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            if requireSecurityScope, !scoped {
                summary.failed += 1
                summary.firstFailureReason = summary.firstFailureReason
                    ?? String(format: String(localized: "import.error.permission_denied_format"), url.lastPathComponent)
                continue
            }

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
                summary.imported += 1
                remaining -= 1
                pendingBatch += 1

                if pendingBatch >= batchSize {
                    try modelContext.save()
                    pendingBatch = 0
                }
            } catch {
                summary.failed += 1
                summary.firstFailureReason = summary.firstFailureReason ?? error.localizedDescription
                continue
            }
        }

        if pendingBatch > 0 {
            try modelContext.save()
        }

        if summary.imported == 0, summary.failed > 0 {
            throw PhotoImporterError.allFilesFailed(
                failures: summary.failed,
                firstReason: summary.firstFailureReason ?? ""
            )
        }

        return summary
    }

    /// Filtre les fichiers selon les extensions supportées et déplie les dossiers de premier niveau.
    /// Les sous-dossiers sont également parcourus de manière non-récursive sur 2 niveaux pour rester rapide.
    private static func expandIntoSupportedFiles(_ urls: [URL]) -> [URL] {
        var results: [URL] = []
        let fm = FileManager.default

        func appendIfSupported(_ u: URL) {
            let ext = u.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { return }
            results.append(u)
        }

        for url in urls {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                /// Énumération non récursive : on prend les fichiers à plat, pas l’intégralité d’une arborescence
                /// (un drop d’un dossier entier remplirait la bibliothèque sans contrôle).
                if let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    for child in contents {
                        appendIfSupported(child)
                    }
                }
            } else {
                appendIfSupported(url)
            }
        }

        return results
    }
}
