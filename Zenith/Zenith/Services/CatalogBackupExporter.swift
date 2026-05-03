//
//  CatalogBackupExporter.swift
//  Zenith
//

import Foundation
import SwiftData

/// Sauvegarde locale du catalogue (métadonnées JSON + réglages), hors fichiers image bruts.
@MainActor
enum CatalogBackupExporter {
    struct Snapshot: Codable {
        var exportedAt: Date
        var photos: [PhotoSnapshot]
        var collections: [CollectionSnapshot]
        var presets: [PresetSnapshot]
    }

    struct PhotoSnapshot: Codable {
        var id: UUID
        var filename: String
        var rating: Int
        var flagRaw: String
        var collectionID: UUID?
        var addedAt: Date
        var pixelWidth: Int
        var pixelHeight: Int
    }

    struct CollectionSnapshot: Codable {
        var collectionUUID: UUID
        var name: String
        var parentID: UUID?
        var sortIndex: Int
    }

    struct PresetSnapshot: Codable {
        var id: UUID
        var name: String
        var settingsBlob: Data
        var createdAt: Date
    }

    static func buildSnapshot(modelContext: ModelContext) throws -> Snapshot {
        let photos = try modelContext.fetch(FetchDescriptor<PhotoRecord>())
        let cols = try modelContext.fetch(FetchDescriptor<CollectionRecord>())
        let presets = try modelContext.fetch(FetchDescriptor<PresetRecord>())
        return Snapshot(
            exportedAt: Date(),
            photos: photos.map {
                PhotoSnapshot(
                    id: $0.id,
                    filename: $0.filename,
                    rating: $0.rating,
                    flagRaw: $0.flagRaw,
                    collectionID: $0.collectionID,
                    addedAt: $0.addedAt,
                    pixelWidth: $0.pixelWidth,
                    pixelHeight: $0.pixelHeight
                )
            },
            collections: cols.map {
                CollectionSnapshot(collectionUUID: $0.collectionUUID, name: $0.name, parentID: $0.parentID, sortIndex: $0.sortIndex)
            },
            presets: presets.map {
                PresetSnapshot(id: $0.id, name: $0.name, settingsBlob: $0.settingsBlob, createdAt: $0.createdAt)
            }
        )
    }

    static func writeJSONSnapshot(to url: URL, modelContext: ModelContext) throws {
        let snap = try buildSnapshot(modelContext: modelContext)
        let data = try JSONEncoder().encode(snap)
        try data.write(to: url, options: [.atomic])
    }
}
