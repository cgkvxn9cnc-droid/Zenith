//
//  ColorProfileReader.swift
//  Zenith
//
//  Lecture des métadonnées colorimétriques (ImageIO) pour l’aperçu Develop.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Métadonnées lues sur le fichier (profil embarqué, modèle de couleur).
nonisolated struct ImageColorDescription: Sendable, Equatable {
    /// Données ICC brutes si présentes dans le fichier.
    let embeddedICCData: Data?
    /// Nom affichable (EXIF / propriété ImageIO ou modèle).
    let profileDisplayName: String?
    let isCMYK: Bool
    /// Espace créé à partir de l’ICC embarqué ; `nil` si absent ou invalide.
    let embeddedColorSpace: CGColorSpace?

    /// Espace RVB source pour `matchedToWorkingSpace(from:)` (fichiers RVB / RVB taggé ou profil assumé).
    /// Ne pas utiliser pour les CMJN ; utiliser la conversion dédiée CMJN → RVB.
    nonisolated func effectiveSourceRGBColorSpace(assumed: ZenithAssumedRGBProfile) -> CGColorSpace {
        if let cs = embeddedColorSpace, !isCMYK { return cs }
        return assumed.cgColorSpace
    }

    /// Libellé pour l’UI (aperçu / info).
    @MainActor
    func statusLabel(assumed: ZenithAssumedRGBProfile) -> String {
        if isCMYK {
            return String(localized: "color.profile.status.cmyk")
        }
        if embeddedICCData != nil || embeddedColorSpace != nil {
            let name = (profileDisplayName?.isEmpty == false) ? profileDisplayName! : String(localized: "color.profile.embedded.unnamed")
            return String(format: String(localized: "color.profile.status.embedded.format"), locale: .current, name)
        }
        return String(format: String(localized: "color.profile.status.assumed.format"), locale: .current, assumed.localizedLabel)
    }
}

/// Lecture ImageIO : ICC, modèle CMJN / RVB.
nonisolated enum ColorProfileReader: Sendable {

    nonisolated static func describe(url: URL) -> ImageColorDescription {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return ImageColorDescription(
                embeddedICCData: nil,
                profileDisplayName: nil,
                isCMYK: false,
                embeddedColorSpace: nil
            )
        }
        return describe(imageSource: src, url: url)
    }

    nonisolated static func describe(imageSource src: CGImageSource, url: URL) -> ImageColorDescription {
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]

        // Clé ImageIO = `kCGImagePropertyICCProfile` ; littéral pour éviter l’isolation MainActor des `let` fichier.
        let iccData = props["ICCProfile" as CFString] as? Data

        var embeddedSpace: CGColorSpace?
        if let icc = iccData {
            embeddedSpace = CGColorSpace(iccData: icc as CFData)
        }

        let colorModel = props[kCGImagePropertyColorModel] as? String
        let isCMYK = colorModel == (kCGImagePropertyColorModelCMYK as String)

        var displayName = props[kCGImagePropertyProfileName] as? String
        if displayName == nil, let space = embeddedSpace {
            displayName = space.name as String?
        }

        return ImageColorDescription(
            embeddedICCData: iccData,
            profileDisplayName: displayName,
            isCMYK: isCMYK,
            embeddedColorSpace: embeddedSpace
        )
    }

    /// Heuristique alignée sur `ZenithImageSourceLoader.isLikelyCameraRAW` : ne pas lire les RAW comme bitmap ICC.
    nonisolated static func describeIfBitmap(url: URL) -> ImageColorDescription? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let typeId = CGImageSourceGetType(src) as String?,
              let ut = UTType(typeId)
        else {
            return nil
        }
        if ut.conforms(to: .rawImage) {
            return nil
        }
        return describe(imageSource: src, url: url)
    }
}
