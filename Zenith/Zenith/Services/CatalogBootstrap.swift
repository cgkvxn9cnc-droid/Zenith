//
//  CatalogBootstrap.swift
//  Zenith
//

import Foundation
import SwiftData

@MainActor
enum CatalogBootstrap {
    /// Insère les dossiers par défaut si besoin et renvoie l’identifiant « Bibliothèque ».
    @discardableResult
    static func seedIfNeeded(modelContext: ModelContext) throws -> UUID? {
        let desc = FetchDescriptor<CollectionRecord>()
        let existing = try modelContext.fetch(desc)
        guard existing.isEmpty else {
            return existing.first { $0.name == "Bibliothèque" }?.collectionUUID
        }
        let libraryID = UUID()
        let library = CollectionRecord(collectionUUID: libraryID, name: "Bibliothèque", parentID: nil, sortIndex: 0)
        let folder = CollectionRecord(name: "Collections", parentID: nil, sortIndex: 1)
        modelContext.insert(library)
        modelContext.insert(folder)
        try modelContext.save()
        return libraryID
    }

    static func libraryCollectionID(from collections: [CollectionRecord]) -> UUID? {
        collections.first { $0.name == "Bibliothèque" }?.collectionUUID
    }
}
