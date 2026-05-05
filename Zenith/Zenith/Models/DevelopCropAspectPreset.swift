//
//  DevelopCropAspectPreset.swift
//  Zenith
//

import Foundation
import SwiftUI

/// Proportions de recadrage (largeur / hauteur de la zone utile).
enum DevelopCropAspectPreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case free
    case original
    case ratio1_1
    case ratio4_3
    case ratio3_4
    case ratio3_2
    case ratio2_3
    case ratio16_9
    case ratio9_16

    var id: String { rawValue }

    /// Ratio largeur ÷ hauteur ; `nil` = libre (pas de contrainte à la redimension).
    func widthOverHeight(imageNaturalRatio: CGFloat) -> CGFloat? {
        switch self {
        case .free:
            return nil
        case .original:
            guard imageNaturalRatio > 0 else { return nil }
            return imageNaturalRatio
        case .ratio1_1:
            return 1
        case .ratio4_3:
            return 4 / 3
        case .ratio3_4:
            return 3 / 4
        case .ratio3_2:
            return 3 / 2
        case .ratio2_3:
            return 2 / 3
        case .ratio16_9:
            return 16 / 9
        case .ratio9_16:
            return 9 / 16
        }
    }

    var labelKey: LocalizedStringKey {
        switch self {
        case .free: "develop.crop.aspect.free"
        case .original: "develop.crop.aspect.original"
        case .ratio1_1: "develop.crop.aspect.1_1"
        case .ratio4_3: "develop.crop.aspect.4_3"
        case .ratio3_4: "develop.crop.aspect.3_4"
        case .ratio3_2: "develop.crop.aspect.3_2"
        case .ratio2_3: "develop.crop.aspect.2_3"
        case .ratio16_9: "develop.crop.aspect.16_9"
        case .ratio9_16: "develop.crop.aspect.9_16"
        }
    }
}
