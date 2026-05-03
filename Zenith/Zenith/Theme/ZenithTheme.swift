//
//  ZenithTheme.swift
//  Zenith
//

import SwiftUI

enum ZenithTheme {
    /// Gris moyen ~50 % pour le canevas principal.
    static let canvasBackground = Color(red: 0.5, green: 0.5, blue: 0.52)

    static let glassStroke = Color.white.opacity(0.12)

    static let accent = Color.accentColor

    /// Accent « réglages » type Pixelmator / captures de référence.
    static let adjustmentOrange = Color(red: 1.0, green: 0.48, blue: 0.12)

    /// Fond des cartes du panneau de développement.
    static let developCardFill = Color(red: 0.16, green: 0.16, blue: 0.17)

    static let developPanelBackground = Color(red: 0.09, green: 0.09, blue: 0.1)

    /// Barre latérale gauche : coins arrondis côté contenu (bord intérieur).
    static var sidebarGlassShapeLeading: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 18,
            topTrailingRadius: 18,
            style: .continuous
        )
    }

    /// Barre latérale droite : coins arrondis côté contenu.
    static var sidebarGlassShapeTrailing: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 18,
            bottomLeadingRadius: 18,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    /// Verre « liquid » pour les colonnes latérales (effet plus lisible sur le canevas).
    @ViewBuilder
    static func liquidSidebarGlass<S: Shape>(_ shape: S) -> some View {
        if #available(macOS 26.0, *) {
            shape
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: shape)
                .overlay(shape.stroke(glassStroke, lineWidth: 1))
        } else {
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.stroke(glassStroke, lineWidth: 1))
        }
    }

    @ViewBuilder
    static func glassPanel<S: Shape>(_ shape: S) -> some View {
        liquidSidebarGlass(shape)
    }
}
