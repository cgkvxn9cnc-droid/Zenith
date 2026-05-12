//
//  CollectionRecord.swift
//  Zenith
//

import Foundation
import SwiftData

@Model
final class CollectionRecord {
    /// Identifiant stable (évite le conflit avec `PersistentModel.id`).
    @Attribute(.unique) var collectionUUID: UUID
    var name: String
    var parentID: UUID?
    var sortIndex: Int
    /// Date de création du dossier : sert au tri « par date » dans la barre latérale.
    /// Valeur par défaut indispensable pour la migration légère SwiftData (les dossiers existants reçoivent l’instant de migration).
    var createdAt: Date = Date()

    init(collectionUUID: UUID = UUID(), name: String, parentID: UUID? = nil, sortIndex: Int = 0, createdAt: Date = Date()) {
        self.collectionUUID = collectionUUID
        self.name = name
        self.parentID = parentID
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }
}
