//
//  WorkspaceHierarchyMode.swift
//  Zenith
//

import Foundation

/// Modes visibles en permanence : bibliothèque (grille) et développement (le catalogue est dans le menu Fichier).
enum WorkspaceHierarchyMode: String, CaseIterable, Identifiable {
    case library
    case develop

    var id: String { rawValue }
}
