//
//  DevelopSettings+GroupReset.swift
//  Zenith
//

import Foundation

extension DevelopSettings {
    /// Valeurs par défaut d’une seule carte (toggle + paramètres), sans toucher aux autres réglages.
    mutating func resetWhiteBalanceGroup() {
        let n = Self.neutral
        enableWhiteBalance = n.enableWhiteBalance
        temperature = n.temperature
        tint = n.tint
    }

    mutating func resetBasicGroup() {
        let n = Self.neutral
        enableBasicAdjustments = n.enableBasicAdjustments
        exposureEV = n.exposureEV
        brightness = n.brightness
        contrast = n.contrast
        highlights = n.highlights
        shadows = n.shadows
        blackPoint = n.blackPoint
        clarity = n.clarity
        texture = n.texture
    }

    mutating func resetHueSaturationGroup() {
        let n = Self.neutral
        enableHueSaturation = n.enableHueSaturation
        tslHue = n.tslHue
        tslSaturation = n.tslSaturation
        tslLuminance = n.tslLuminance
        saturation = n.saturation
        vibrance = n.vibrance
    }

    /// Carte unique « Basiques » : balance des blancs + exposition / tons + teinte / saturation.
    mutating func resetBasicsPanelGroup() {
        resetWhiteBalanceGroup()
        resetBasicGroup()
        resetHueSaturationGroup()
    }

    /// Carte « Grain et bruit ».
    mutating func resetGrainAndNoiseGroup() {
        resetNoiseReductionGroup()
        resetGrainGroup()
    }

    mutating func resetSelectiveClarityGroup() {
        let n = Self.neutral
        enableSelectiveClarity = n.enableSelectiveClarity
        selectiveClarityTone = n.selectiveClarityTone
    }

    mutating func resetSelectiveColorGroup() {
        let n = Self.neutral
        enableSelectiveColor = n.enableSelectiveColor
        selectivePalette = n.selectivePalette
    }

    mutating func resetColorBalanceGroup() {
        let n = Self.neutral
        enableColorBalance = n.enableColorBalance
        cbHighlightHue = n.cbHighlightHue
        cbHighlightSaturation = n.cbHighlightSaturation
        cbMidtoneHue = n.cbMidtoneHue
        cbMidtoneSaturation = n.cbMidtoneSaturation
        cbShadowHue = n.cbShadowHue
        cbShadowSaturation = n.cbShadowSaturation
    }

    mutating func resetLevelsGroup() {
        let n = Self.neutral
        enableLevels = n.enableLevels
        levelsInputBlack = n.levelsInputBlack
        levelsInputWhite = n.levelsInputWhite
        levelsMidtone = n.levelsMidtone
    }

    mutating func resetCurvesGroup() {
        let n = Self.neutral
        enableCurves = n.enableCurves
        toneCurveMaster = n.toneCurveMaster
        toneCurveRed = n.toneCurveRed
        toneCurveGreen = n.toneCurveGreen
        toneCurveBlue = n.toneCurveBlue
    }

    mutating func resetRemoveColorGroup() {
        let n = Self.neutral
        enableRemoveColor = n.enableRemoveColor
        removeColorHueKey = n.removeColorHueKey
        removeColorRange = n.removeColorRange
        removeColorLumaRange = n.removeColorLumaRange
        removeColorIntensity = n.removeColorIntensity
    }

    mutating func resetBlackWhiteGroup() {
        let n = Self.neutral
        enableBlackWhite = n.enableBlackWhite
        bwRed = n.bwRed
        bwGreen = n.bwGreen
        bwBlue = n.bwBlue
        bwTone = n.bwTone
        bwIntensity = n.bwIntensity
    }

    mutating func resetLUTGroup() {
        let n = Self.neutral
        enableLUT = n.enableLUT
        lutPresetIndex = n.lutPresetIndex
        lutMix = n.lutMix
    }

    mutating func resetVignetteGroup() {
        let n = Self.neutral
        enableVignetting = n.enableVignetting
        vignetteExposureAmount = n.vignetteExposureAmount
        vignetteSoftnessAmount = n.vignetteSoftnessAmount
        vignetteBlackPointAmount = n.vignetteBlackPointAmount
    }

    mutating func resetSharpnessGroup() {
        let n = Self.neutral
        enableSharpness = n.enableSharpness
        sharpnessRadiusPx = n.sharpnessRadiusPx
        sharpnessAmountPct = n.sharpnessAmountPct
        sharpnessDetailPct = n.sharpnessDetailPct
        sharpnessMaskingPct = n.sharpnessMaskingPct
    }

    mutating func resetGrainGroup() {
        let n = Self.neutral
        enableGrain = n.enableGrain
        grainSizePct = n.grainSizePct
        grainIntensityPct = n.grainIntensityPct
        grainRoughnessPct = n.grainRoughnessPct
    }

    mutating func resetSharpnessGrainGroup() {
        resetSharpnessGroup()
        resetGrainGroup()
    }

    mutating func resetLensGroup() {
        let n = Self.neutral
        enableLensCorrection = n.enableLensCorrection
        lensCorrection = n.lensCorrection
        chromaticAberration = n.chromaticAberration
    }

    mutating func resetMasksGroup() {
        let n = Self.neutral
        enableMasks = n.enableMasks
        maskRadialBlend = n.maskRadialBlend
    }

    mutating func resetTSLPerColorGroup() {
        let n = Self.neutral
        enableTSLPerColor = n.enableTSLPerColor
        tslPerColorPalette = n.tslPerColorPalette
    }

    mutating func resetNoiseReductionGroup() {
        let n = Self.neutral
        enableNoiseReduction = n.enableNoiseReduction
        noiseReductionLuminance = n.noiseReductionLuminance
        noiseReductionChrominance = n.noiseReductionChrominance
    }

    mutating func resetToneMappingGroup() {
        let n = Self.neutral
        enableToneMapping = n.enableToneMapping
        toneMappingContrast = n.toneMappingContrast
        toneMappingPivotEV = n.toneMappingPivotEV
        toneMappingWhitePoint = n.toneMappingWhitePoint
    }

    /// Désactive et neutralise les réglages dont les cartes ont été retirées du panneau Développement
    /// (migration catalogue / préréglages — voir `DevelopRemovedPanelEffectsMigration`).
    mutating func stripEffectsOfRemovedDevelopPanelTools() {
        resetToneMappingGroup()
        resetSelectiveClarityGroup()
        resetSelectiveColorGroup()
        resetLevelsGroup()
        resetRemoveColorGroup()
        resetVignetteGroup()
        resetLUTGroup()
        resetLensGroup()
        resetMasksGroup()

        enableToneMapping = false
        enableLevels = false
        enableSelectiveClarity = false
        enableSelectiveColor = false
        enableRemoveColor = false
        enableVignetting = false
        enableLUT = false
        enableLensCorrection = false
        enableMasks = false

        brightness = Self.neutral.brightness
        saturation = Self.neutral.saturation
        vibrance = Self.neutral.vibrance
        tslLuminance = Self.neutral.tslLuminance
    }

    mutating func resetCropToFullFrame() {
        let n = Self.neutral
        cropLeft = n.cropLeft
        cropTop = n.cropTop
        cropRight = n.cropRight
        cropBottom = n.cropBottom
        cropNormalizedOriginX = n.cropNormalizedOriginX
        cropNormalizedOriginY = n.cropNormalizedOriginY
        cropNormalizedWidth = n.cropNormalizedWidth
        cropNormalizedHeight = n.cropNormalizedHeight
        cropFlipHorizontal = n.cropFlipHorizontal
        cropFlipVertical = n.cropFlipVertical
        cropAspectPresetRaw = DevelopCropAspectPreset.free.rawValue
        straightenAngle = n.straightenAngle
    }
}
