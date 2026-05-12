//
//  DevelopPipelineColorMath.swift
//  Zenith
//

import Foundation

/// Transferts sRGB IEC 61966 + mixer N&B + LUT niveaux « perceptuelle » (domaine codé puis retour linéaire).
nonisolated enum DevelopPipelineColorMath {

    /// Poids canal type Lightroom : Rec.709 + offsets (-100…100), re-clamp puis normalisation Σ = 1.
    static func blackWhiteChannelWeights(bwRed: Double, bwGreen: Double, bwBlue: Double) -> (wr: Double, wg: Double, wb: Double) {
        let baseR = 0.2126
        let baseG = 0.7152
        let baseB = 0.0722
        let scale = 0.002 // +100 ⇒ +0.2 sur le canal ciblé avant norm.
        var wr = baseR + bwRed * scale
        var wg = baseG + bwGreen * scale
        var wb = baseB + bwBlue * scale
        wr = max(0, wr)
        wg = max(0, wg)
        wb = max(0, wb)
        let sum = wr + wg + wb
        guard sum > 1e-9 else { return (baseR, baseG, baseB) }
        return (wr / sum, wg / sum, wb / sum)
    }

    /// Une composante RVB linéaire sRGB dans [0,1] vers valeur codée (non linéaire) affichée.
    static func linearSRGBChannelToEncoded(_ lin: Double) -> Double {
        let x = min(1, max(0, lin))
        if x <= 0.0031308 { return 12.92 * x }
        return 1.055 * pow(x, 1.0 / 2.4) - 0.055
    }

    /// Décode une valeur codée sRGB [0,1] vers linéaire.
    static func encodedSRGBChannelToLinear(_ encoded: Double) -> Double {
        let x = min(1, max(0, encoded))
        if x <= 0.04045 { return x / 12.92 }
        return pow((x + 0.055) / 1.055, 2.4)
    }

    /// LUT linéaire → linéaire : étirement noir/blanc + pivô médian comme Photoshop, mais appliqué sur l’axe **codé** (perceptif).
    static func rgbLevelsPerceptualLUT(
        inputBlackPct: Double,
        inputWhitePct: Double,
        midtonePct: Double,
        sampleCount: Int
    ) -> [Double] {
        let sampleCountResolved = max(4, sampleCount)
        let blackIn = min(1, max(0, inputBlackPct / 100))
        var whiteIn = min(1, max(0, inputWhitePct / 100))
        if whiteIn <= blackIn + 1e-4 {
            whiteIn = blackIn + 1e-4
        }
        let midMapped = min(1 - 1e-4, max(1e-4, midtonePct / 100))
        let midDisp = min(whiteIn - 1e-4, max(blackIn + 1e-4, midMapped))
        let t = (midDisp - blackIn) / (whiteIn - blackIn)
        let gamma: Double = {
            if t <= 1e-6 || t >= 1 - 1e-6 { return 1.0 }
            let g = log(0.5) / log(t)
            if g.isFinite, g > 0.02, g < 50 { return g }
            return 1.0
        }()
        var samples: [Double] = []
        samples.reserveCapacity(sampleCountResolved)
        let invRange = 1.0 / (whiteIn - blackIn)
        for j in 0 ..< sampleCountResolved {
            let xLin = Double(j) / Double(sampleCountResolved - 1)
            let xDisp = linearSRGBChannelToEncoded(xLin)
            var stretched = (xDisp - blackIn) * invRange
            stretched = min(1, max(0, stretched))
            let yDisp = pow(stretched, gamma)
            let yLin = encodedSRGBChannelToLinear(yDisp)
            samples.append(min(1, max(0, yLin)))
        }
        return samples
    }

    // MARK: - Réponse « douce » des curseurs (UI inchangée, rendu moins brutal près du neutre)

    /// Curseurs symétriques type ±100 : proche de 0 la courbe est plus progressive, les extrêmes restent atteignables.
    /// `exponent` > 1 adoucit le centre (ex. 1,2 ⇒ ~40 % d’effet réel à mi-course affichée).
    static func softenSigned100(_ value: Double, exponent: Double = 1.18) -> Double {
        let t = min(100, max(-100, value)) / 100
        if abs(t) < 1e-12 { return 0 }
        let mag = pow(abs(t), exponent)
        return (t > 0 ? 1 : -1) * mag * 100
    }

    /// Curseurs 0…`maxValue` (saturation, netteté, grain…) : montée douce depuis zéro.
    static func softenUnsigned(_ value: Double, maxValue: Double = 100, exponent: Double = 1.12) -> Double {
        guard maxValue > 0 else { return 0 }
        let u = min(maxValue, max(0, value)) / maxValue
        return maxValue * pow(u, exponent)
    }

    /// Exposition EV sur ±`halfRange` : moins « nerveuse » sur les petits réglages (ex. ±1 EV).
    static func softenSignedEV(_ ev: Double, halfRange: Double = 4, exponent: Double = 1.22) -> Double {
        guard halfRange > 0 else { return ev }
        let t = min(1, max(-1, ev / halfRange))
        if abs(t) < 1e-12 { return 0 }
        let mag = pow(abs(t), exponent)
        return (t > 0 ? 1 : -1) * mag * halfRange
    }
}
