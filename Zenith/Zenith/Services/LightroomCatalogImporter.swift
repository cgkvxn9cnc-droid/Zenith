//
//  LightroomCatalogImporter.swift
//  Zenith
//
//  Lecture en lecture seule d’un catalogue Adobe Lightroom Classic (*.lrcat, SQLite) et import
//  des fichiers maîtres référencés dans le catalogue SwiftData courant.
//
//  Limites volontaires (v1) :
//  - Pas d’import des réglages Lightroom / XMP dans Develop ; neutral Zenith.
//  - Collections Lightroom importées comme dossiers Zenith (une appartenance par photo).
//  - Schéma testé sur la lignée LR documentée (AgLibrary*, Adobe_images) ; versions très récentes
//    peuvent diverger → message d’erreur explicite.
//

import AppKit
import Foundation
import SQLite3
import SwiftData
import UniformTypeIdentifiers

enum LightroomImportError: LocalizedError {
    case cannotOpenDatabase(String)
    case unsupportedCatalog(String)
    case noMasterImagesFound
    case userCancelledAccess

    var errorDescription: String? {
        switch self {
        case .cannotOpenDatabase(let msg):
            return String(format: String(localized: "lr.import.error.sqlite_format"), msg)
        case .unsupportedCatalog(let msg):
            return msg
        case .noMasterImagesFound:
            return String(localized: "lr.import.error.no_images")
        case .userCancelledAccess:
            return String(localized: "lr.import.error.access_cancelled")
        }
    }
}

/// Ligne décrite dans `Adobe_images` + chemins résolus via AgLibraryFile / dossiers.
private struct LightroomMasterRow {
    let imageId: Int64
    let absolutePath: String
    let rating: Int
}

/// Import Lightroom → Zenith (catalogue déjà ouvert).
@MainActor
enum LightroomCatalogImporter {

    /// Ouvre un panneau pour choisir un `.lrcat`, puis importe les fichiers accessibles.
    @discardableResult
    static func importViaOpenPanel(
        modelContext: ModelContext,
        currentPhotoCount: Int,
        collections: [CollectionRecord]
    ) throws -> PhotoImportSummary {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = String(localized: "lr.import.panel_title")
        panel.message = String(localized: "lr.import.panel_message")
        if let lrcat = UTType(filenameExtension: "lrcat") {
            panel.allowedContentTypes = [lrcat]
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return PhotoImportSummary()
        }

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        return try importFromLRCAT(
            at: url,
            modelContext: modelContext,
            currentPhotoCount: currentPhotoCount,
            collections: collections
        )
    }

    /// Import à partir d’une URL `.lrcat` (portée sécurisée déjà active si nécessaire).
    static func importFromLRCAT(
        at lrcatURL: URL,
        modelContext: ModelContext,
        currentPhotoCount: Int,
        collections: [CollectionRecord]
    ) throws -> PhotoImportSummary {
        guard currentPhotoCount < PhotoImporter.maxPhotos else {
            throw PhotoImporterError.catalogLimitReached(PhotoImporter.maxPhotos)
        }

        try CatalogBootstrap.seedIfNeeded(modelContext: modelContext)

        let masters = try Self.fetchMasterRows(fromCatalogURL: lrcatURL)
        guard !masters.isEmpty else {
            throw LightroomImportError.noMasterImagesFound
        }

        let roots = try Self.fetchRootFolderPaths(fromCatalogURL: lrcatURL)
        guard !roots.isEmpty else {
            throw LightroomImportError.unsupportedCatalog(
                String(localized: "lr.import.error.no_root_folders")
            )
        }

        /// Dossiers accordés par l’utilisateur (signets + portée active).
        var granted: [(url: URL, stop: () -> Void)] = []
        defer {
            for g in granted {
                g.stop()
            }
        }

        for rootPath in roots {
            let standardizedRoot = rootPath.standardizedPath
            let exists = FileManager.default.fileExists(atPath: standardizedRoot)
            let startURL = exists
                ? URL(fileURLWithPath: standardizedRoot, isDirectory: true)
                : FileManager.default.homeDirectoryForCurrentUser

            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.directoryURL = startURL
            panel.title = String(localized: "lr.import.grant_folder_title")
            if exists {
                panel.message = String(
                    format: String(localized: "lr.import.grant_folder_message_format"),
                    locale: .current,
                    startURL.lastPathComponent
                )
            } else {
                panel.message = String(
                    format: String(localized: "lr.import.grant_folder_missing_format"),
                    locale: .current,
                    standardizedRoot
                )
            }

            guard panel.runModal() == .OK, let picked = panel.url else {
                continue
            }

            guard picked.startAccessingSecurityScopedResource() else {
                continue
            }
            granted.append((picked, { picked.stopAccessingSecurityScopedResource() }))
        }

        if granted.isEmpty {
            throw LightroomImportError.unsupportedCatalog(
                String(localized: "lr.import.error.no_roots_on_disk")
            )
        }

        let grantedPrefixes = granted.map { $0.url.standardizedFileURL.path.standardizedPathWithTrailingSlash }

        let collectionsFolderID = collections.first(where: { $0.name == "Collections" })?.collectionUUID
        let lrCollectionMapping = try Self.importLightroomCollections(
            modelContext: modelContext,
            lrcatURL: lrcatURL,
            collectionsFolderUUID: collectionsFolderID,
            existingCollections: collections
        )

        var summary = PhotoImportSummary()
        var remaining = PhotoImporter.maxPhotos - currentPhotoCount
        let batchSize = 50
        var pendingBatch = 0

        /// image Lightroom id_local → premier dossier Zenith (collection UUID).
        var imageToCollection: [Int64: UUID] = [:]
        if let m = lrCollectionMapping {
            imageToCollection = try Self.fetchImageCollectionMapping(
                fromCatalogURL: lrcatURL,
                lrCollectionToZenith: m
            )
        }

        for row in masters {
            guard remaining > 0 else {
                summary.skipped += 1
                continue
            }

            let fullPath = row.absolutePath.standardizedPath
            guard Self.path(fullPath, isUnderAnyGrantedPrefix: grantedPrefixes) else {
                summary.skipped += 1
                continue
            }

            let fileURL = URL(fileURLWithPath: fullPath)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                summary.skipped += 1
                continue
            }

            let ext = fileURL.pathExtension.lowercased()
            guard PhotoImporter.supportedExtensions.contains(ext) else {
                summary.skipped += 1
                continue
            }

            /// Réutiliser la portée du dossier parent déjà ouverte : bookmark fichier.
            let scopedParent = granted.first { prefixURL in
                fullPath.hasPrefix(prefixURL.url.standardizedFileURL.path.standardizedPathWithTrailingSlash)
                    || fullPath == prefixURL.url.standardizedFileURL.path
            }
            guard scopedParent != nil else {
                summary.skipped += 1
                continue
            }

            do {
                let bookmark = try SecurityScoped.bookmark(for: fileURL)
                let dims = ThumbnailLoader.pixelSize(of: fileURL)
                let collectionID = imageToCollection[row.imageId]
                    ?? CatalogBootstrap.libraryCollectionID(from: collections)

                let photo = PhotoRecord(
                    fileBookmark: bookmark,
                    filename: fileURL.lastPathComponent,
                    rating: min(5, max(0, row.rating)),
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

    // MARK: - SQLite

    private static func openReadonly(_ url: URL) throws -> OpaquePointer {
        var db: OpaquePointer?
        let path = url.path
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database = db else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "sqlite"
            if let d = db { sqlite3_close(d) }
            throw LightroomImportError.cannotOpenDatabase(msg)
        }
        sqlite3_busy_timeout(database, 5_000)
        return database
    }

    private static func fetchMasterRows(fromCatalogURL: URL) throws -> [LightroomMasterRow] {
        let db = try openReadonly(fromCatalogURL)
        defer { sqlite3_close(db) }

        guard Self.tableExists("Adobe_images", db: db),
              Self.tableExists("AgLibraryFile", db: db),
              Self.tableExists("AgLibraryFolder", db: db),
              Self.tableExists("AgLibraryRootFolder", db: db) else {
            throw LightroomImportError.unsupportedCatalog(
                String(localized: "lr.import.error.missing_tables")
            )
        }

        let sql = """
        SELECT
          img.id_local,
          img.rating,
          rf.absolutePath,
          IFNULL(fo.pathFromRoot, ''),
          fi.baseName,
          fi."extension"
        FROM Adobe_images AS img
        INNER JOIN AgLibraryFile AS fi ON img.rootFile = fi.id_local
        INNER JOIN AgLibraryFolder AS fo ON fi.folder = fo.id_local
        INNER JOIN AgLibraryRootFolder AS rf ON fo.rootFolder = rf.id_local
        WHERE img.masterImage IS NULL
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            throw LightroomImportError.unsupportedCatalog(
                String(localized: "lr.import.error.query_prepare")
            )
        }
        defer { sqlite3_finalize(statement) }

        var rows: [LightroomMasterRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let imageId = sqlite3_column_int64(statement, 0)
            let ratingDouble = sqlite3_column_type(statement, 1) == SQLITE_NULL
                ? 0.0
                : sqlite3_column_double(statement, 1)
            let rating = min(5, max(0, Int(round(ratingDouble))))

            guard let rootC = sqlite3_column_text(statement, 2) else { continue }
            let rootPath = String(cString: rootC)

            let pathFromRoot: String = {
                guard sqlite3_column_type(statement, 3) != SQLITE_NULL,
                      let pr = sqlite3_column_text(statement, 3) else { return "" }
                return String(cString: pr)
            }()

            guard let baseC = sqlite3_column_text(statement, 4),
                  let extC = sqlite3_column_text(statement, 5) else { continue }
            let baseName = String(cString: baseC)
            let ext = String(cString: extC)

            let composed = Self.composeAbsolutePath(root: rootPath, pathFromRoot: pathFromRoot, baseName: baseName, ext: ext)
            rows.append(LightroomMasterRow(imageId: imageId, absolutePath: composed, rating: rating))
        }

        return rows
    }

    private static func fetchRootFolderPaths(fromCatalogURL: URL) throws -> [String] {
        let db = try openReadonly(fromCatalogURL)
        defer { sqlite3_close(db) }

        guard Self.tableExists("AgLibraryRootFolder", db: db) else { return [] }

        let sql = "SELECT absolutePath FROM AgLibraryRootFolder WHERE absolutePath IS NOT NULL AND length(trim(absolutePath)) > 0"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var paths: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let c = sqlite3_column_text(statement, 0) else { continue }
            paths.append(String(cString: c).standardizedPath)
        }
        return Array(Set(paths)).sorted()
    }

    private static func tableExists(_ name: String, db: OpaquePointer) -> Bool {
        let sql = "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let st = stmt else { return false }
        defer { sqlite3_finalize(st) }
        /// Équivalent de `SQLITE_TRANSIENT` (copie la chaîne ; non exposé par l’overlay Swift sur certaines cibles).
        let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = name.withCString { ptr in
            sqlite3_bind_text(st, 1, ptr, -1, transientDestructor)
        }
        return sqlite3_step(st) == SQLITE_ROW
    }

    private static func composeAbsolutePath(root: String, pathFromRoot: String, baseName: String, ext: String) -> String {
        let r = (root as NSString).standardizingPath
        let sub = pathFromRoot.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let dir: String = sub.isEmpty ? r : (r as NSString).appendingPathComponent(sub)
        let file = ext.isEmpty ? baseName : "\(baseName).\(ext)"
        return (dir as NSString).appendingPathComponent(file).standardizedPath
    }

    private static func path(_ path: String, isUnderAnyGrantedPrefix prefixes: [String]) -> Bool {
        let p = path.standardizedPath
        for pref in prefixes {
            if p.hasPrefix(pref) { return true }
            if p == pref.trimmingCharacters(in: CharacterSet(charactersIn: "/")) { return true }
        }
        return false
    }

    // MARK: - Collections Lightroom

    /// Retourne la correspondance id collection LR → UUID Zenith pour les collections utilisateur.
    private static func importLightroomCollections(
        modelContext: ModelContext,
        lrcatURL: URL,
        collectionsFolderUUID: UUID?,
        existingCollections: [CollectionRecord]
    ) throws -> [Int64: UUID]? {
        guard let parentColl = collectionsFolderUUID else { return nil }

        let db = try openReadonly(lrcatURL)
        defer { sqlite3_close(db) }

        guard Self.tableExists("AgLibraryCollection", db: db) else { return nil }

        let sql = """
        SELECT id_local, name FROM AgLibraryCollection
        WHERE name IS NOT NULL AND trim(name) != ''
          AND creationId = 'com.adobe.ag.library.collection'
          AND (systemOnly IS NULL OR systemOnly = 0)
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        struct Row { let id: Int64; let name: String }
        var parsed: [Row] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            guard let nameC = sqlite3_column_text(statement, 1) else { continue }
            let name = String(cString: nameC)
            parsed.append(Row(id: id, name: name))
        }
        guard !parsed.isEmpty else { return nil }

        var zenithByLR: [Int64: UUID] = [:]
        let baseSort = (existingCollections.filter { $0.parentID == parentColl }.map(\.sortIndex).max() ?? 0)

        for (idx, row) in parsed.enumerated() {
            let rec = CollectionRecord(name: row.name, parentID: parentColl, sortIndex: baseSort + idx + 1)
            modelContext.insert(rec)
            zenithByLR[row.id] = rec.collectionUUID
        }
        try modelContext.save()

        return zenithByLR.isEmpty ? nil : zenithByLR
    }

    private static func fetchImageCollectionMapping(
        fromCatalogURL: URL,
        lrCollectionToZenith: [Int64: UUID]
    ) throws -> [Int64: UUID] {
        let db = try openReadonly(fromCatalogURL)
        defer { sqlite3_close(db) }

        guard Self.tableExists("AgLibraryCollectionImage", db: db) else { return [:] }

        let sql = """
        SELECT image, collection FROM AgLibraryCollectionImage
        ORDER BY collection, IFNULL(positionInCollection, 0)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            return [:]
        }
        defer { sqlite3_finalize(statement) }

        var first: [Int64: UUID] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let imageId = sqlite3_column_int64(statement, 0)
            let collId = sqlite3_column_int64(statement, 1)
            guard let zu = lrCollectionToZenith[collId] else { continue }
            if first[imageId] == nil {
                first[imageId] = zu
            }
        }
        return first
    }
}

// MARK: - Helpers

private extension String {
    var standardizedPath: String {
        (self as NSString).standardizingPath
    }

    var standardizedPathWithTrailingSlash: String {
        let p = standardizedPath
        return p.hasSuffix("/") ? p : p + "/"
    }
}
