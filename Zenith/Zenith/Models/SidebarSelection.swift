//
//  SidebarSelection.swift
//  Zenith
//

import Foundation

/// Sélection dans la barre latérale : collection ou regroupement par mois d’import.
enum SidebarSelection: Hashable, Sendable {
    case collection(UUID)
    case monthYear(year: Int, month: Int)
}
