//
//  WorkspaceHierarchyMode.swift
//  Zenith
//

import Foundation

/// Les trois zones de travail : catalogue (vue d'ensemble), bibliothèque (tri/grille) et développement (retouche).
enum WorkspaceTab: String, CaseIterable, Identifiable {
    case catalog
    case library
    case develop

    var id: String { rawValue }
}

/// Alias rétro-compatible — à supprimer une fois toutes les références migrées.
typealias WorkspaceHierarchyMode = WorkspaceTab
