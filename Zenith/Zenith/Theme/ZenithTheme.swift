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

    // MARK: - Colonnes latérales (largeurs et marges harmonisées entre Bibliothèque / Catalogue / Développement)

    /// Largeur unique de la colonne gauche (navigation + marges liste après correction du padding).
    static let sidebarLeadingColumnWidth: CGFloat = 288
    /// Largeur unique de la colonne droite (métadonnées bibliothèque · réglages développement).
    static let sidebarTrailingColumnWidth: CGFloat = 336

    /// Marge horizontale interne commune aux colonnes (titres, listes, métadonnées, développement).
    static let sidebarColumnHorizontalPadding: CGFloat = 14
    /// Espacement vertical autour du premier bloc sous la ligne de séparation (segmented).
    static let sidebarColumnSectionVerticalPadding: CGFloat = 10

    /// Barre latérale flottante : tous les coins restent visibles quand le panneau est inset sous la barre du haut.
    static var sidebarFloatingGlassShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
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

    /// Variante très allégée du verre : utilisée pour la barre du haut afin de discerner l’image qui passe derrière.
    @ViewBuilder
    static func translucentChromeGlass<S: Shape>(_ shape: S) -> some View {
        if #available(macOS 26.0, *) {
            shape
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: shape)
                .overlay(shape.fill(Color.black.opacity(0.04)))
                .overlay(shape.stroke(glassStroke.opacity(0.85), lineWidth: 1))
        } else {
            shape
                .fill(.ultraThinMaterial)
                .opacity(0.78)
                .overlay(shape.stroke(glassStroke.opacity(0.85), lineWidth: 1))
        }
    }

    @ViewBuilder
    static func glassPanel<S: Shape>(_ shape: S) -> some View {
        liquidSidebarGlass(shape)
    }
}
