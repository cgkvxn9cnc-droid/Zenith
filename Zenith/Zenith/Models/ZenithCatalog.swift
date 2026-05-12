//
//  ZenithCatalog.swift
//  Zenith
//

import Foundation
import SwiftData

/// Métadonnées d'un catalogue Zenith (`.zenithcatalog` bundle sur disque).
/// Le catalogue encapsule un `ModelContainer` SwiftData contenant photos, collections, préréglages et messages.
struct ZenithCatalog: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var fileURL: URL
    var createdAt: Date
    var lastOpenedAt: Date

    init(name: String, fileURL: URL) {
        self.id = UUID()
        self.name = name
        self.fileURL = fileURL
        self.createdAt = .now
        self.lastOpenedAt = .now
    }
}

/// Entrée légère stockée dans UserDefaults pour la liste des catalogues récents.
/// `bookmarkData` (security‑scoped) est requis sous sandbox pour pouvoir rouvrir le catalogue après fermeture de l’app.
struct RecentCatalogEntry: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    /// Emplacement pour l’UI ; ouverture depuis les récents doit utiliser `bookmarkData`.
    var fileURL: URL
    var lastOpenedAt: Date
    var bookmarkData: Data?

    init(id: UUID, name: String, fileURL: URL, lastOpenedAt: Date, bookmarkData: Data? = nil) {
        self.id = id
        self.name = name
        self.fileURL = fileURL
        self.lastOpenedAt = lastOpenedAt
        self.bookmarkData = bookmarkData
    }
}
