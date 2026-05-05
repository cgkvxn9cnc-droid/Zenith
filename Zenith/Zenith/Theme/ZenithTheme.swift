//
//  ZenithTheme.swift
//  Zenith
//

import SwiftUI

enum ZenithTheme {
    /// Gris moyen à ~50 % de luminance : fond des pages (aperçu, grille, fenêtres).
    static let pageBackground = Color(white: 0.5)

    /// Alias historique : même teinte que `pageBackground`.
    static let canvasBackground = pageBackground

    static let glassStroke = Color.white.opacity(0.12)

    static let accent = Color.accentColor

    /// Accent « réglages » type Pixelmator / captures de référence.
    static let adjustmentOrange = Color(red: 1.0, green: 0.48, blue: 0.12)

    /// Curseurs au-dessus des dégradés : lisible sans masquer la piste colorée.
    static let sliderThumbNeutral = Color(white: 0.88)

    /// Fond des cartes du panneau de développement (légèrement sous le gris page).
    static let developCardFill = Color(white: 0.46)

    static let developPanelBackground = pageBackground

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

    /// Barre chrome supérieure : coins arrondis (flotte sous la zone titre).
    static var topChromeGlassShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    /// Verre « liquid » pour les colonnes latérales et la barre chrome (effet plus lisible sur le canevas).
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
