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

    init(collectionUUID: UUID = UUID(), name: String, parentID: UUID? = nil, sortIndex: Int = 0) {
        self.collectionUUID = collectionUUID
        self.name = name
        self.parentID = parentID
        self.sortIndex = sortIndex
    }
}
