//
//  CropState.swift
//  Zenith
//

import CoreGraphics
import Foundation

/// État logique du recadrage : tout est **indépendant** de la résolution d’affichage / d’export.
/// `rect` est exprimé dans le repère Core Image (origine **bas‑gauche**, Y vers le haut), en fractions de la
/// boîte englobante **après** rotation et retournements — même convention que `DevelopCropPipeline`.
nonisolated struct CropState: Equatable, Sendable {
    /// Rectangle normalisé 0…1 dans `rotatedFlipped.extent` (origine bas‑gauche).
    var rect: CGRect
    /// Angle en radians (positif = anti‑horaire, convention Core Graphics).
    var angleRadians: Double
    /// `nil` = libre ; sinon largeur/hauteur cible du ratio (ex. 16×9 → `CGSize(width: 16, height: 9)`).
    var aspectRatio: CGSize?
    var flipHorizontal: Bool
    var flipVertical: Bool
}

nonisolated extension CropState {
    init(from settings: DevelopSettings) {
        let clampedDeg = max(-45, min(45, settings.straightenAngle))
        let radians = clampedDeg * .pi / 180
        let nx = max(0, min(1, settings.cropNormalizedOriginX))
        let ny = max(0, min(1, settings.cropNormalizedOriginY))
        let nw = max(1e-6, min(1 - nx, settings.cropNormalizedWidth))
        let nh = max(1e-6, min(1 - ny, settings.cropNormalizedHeight))
        self.init(
            rect: CGRect(x: nx, y: ny, width: nw, height: nh),
            angleRadians: radians,
            aspectRatio: nil,
            flipHorizontal: settings.cropFlipHorizontal,
            flipVertical: settings.cropFlipVertical
        )
    }
}
