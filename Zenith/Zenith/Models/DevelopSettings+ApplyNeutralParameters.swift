//
//  DevelopSettings+ApplyNeutralParameters.swift
//  Zenith
//
//  Remet à zéro effet les paramètres d’une « sous-carte » lorsqu’on l’active, sans toucher aux autres réglages.
//

import Foundation

extension DevelopSettings {
    /// Balance des blancs : température / teinte.
    mutating func applyNeutralParametersForWhiteBalanceSection() {
        let n = Self.neutral
        temperature = n.temperature
        tint = n.tint
    }

    /// Tons (exposition, contraste, etc.).
    mutating func applyNeutralParametersForBasicTonesSection() {
        let n = Self.neutral
        exposureEV = n.exposureEV
        brightness = n.brightness
        contrast = n.contrast
        highlights = n.highlights
        shadows = n.shadows
        blackPoint = n.blackPoint
        clarity = n.clarity
        texture = n.texture
    }

    /// Teinte / saturation (curseurs globaux + TSL).
    mutating func applyNeutralParametersForHueSaturationSection() {
        let n = Self.neutral
        tslHue = n.tslHue
        tslSaturation = n.tslSaturation
        tslLuminance = n.tslLuminance
        saturation = n.saturation
        vibrance = n.vibrance
    }

    /// Carte Basiques entière (WB + tons + teinte/sat).
    mutating func applyNeutralParametersForBasicsPanel() {
        applyNeutralParametersForWhiteBalanceSection()
        applyNeutralParametersForBasicTonesSection()
        applyNeutralParametersForHueSaturationSection()
    }

    mutating func applyNeutralParametersForTSLPerColor() {
        tslPerColorPalette = Self.neutral.tslPerColorPalette
    }

    mutating func applyNeutralParametersForColorBalance() {
        let n = Self.neutral
        cbHighlightHue = n.cbHighlightHue
        cbHighlightSaturation = n.cbHighlightSaturation
        cbMidtoneHue = n.cbMidtoneHue
        cbMidtoneSaturation = n.cbMidtoneSaturation
        cbShadowHue = n.cbShadowHue
        cbShadowSaturation = n.cbShadowSaturation
    }

    mutating func applyNeutralParametersForCurves() {
        let n = Self.neutral
        toneCurveMaster = n.toneCurveMaster
        toneCurveRed = n.toneCurveRed
        toneCurveGreen = n.toneCurveGreen
        toneCurveBlue = n.toneCurveBlue
    }

    mutating func applyNeutralParametersForBlackWhite() {
        let n = Self.neutral
        bwRed = n.bwRed
        bwGreen = n.bwGreen
        bwBlue = n.bwBlue
        bwTone = n.bwTone
        bwIntensity = n.bwIntensity
    }

    mutating func applyNeutralParametersForSharpness() {
        let n = Self.neutral
        sharpnessRadiusPx = n.sharpnessRadiusPx
        sharpnessAmountPct = n.sharpnessAmountPct
        sharpnessDetailPct = n.sharpnessDetailPct
        sharpnessMaskingPct = n.sharpnessMaskingPct
    }

    mutating func applyNeutralParametersForNoiseReduction() {
        let n = Self.neutral
        noiseReductionLuminance = n.noiseReductionLuminance
        noiseReductionChrominance = n.noiseReductionChrominance
    }

    mutating func applyNeutralParametersForGrain() {
        let n = Self.neutral
        grainSizePct = n.grainSizePct
        grainIntensityPct = n.grainIntensityPct
        grainRoughnessPct = n.grainRoughnessPct
    }
}
