//
//  DevelopSettings.swift
//  Zenith
//

import Foundation

// MARK: - Couleur sélective (8 teintes type référence Pixelmator)

struct SelectiveColorChannel: Codable, Equatable, Sendable {
    var hue: Double
    var saturation: Double
    var luminance: Double

    static let neutral = SelectiveColorChannel(hue: 0, saturation: 0, luminance: 0)
}

struct SelectiveColorPalette: Codable, Equatable, Sendable {
    var channels: [SelectiveColorChannel]

    static let neutral = SelectiveColorPalette(channels: Array(repeating: .neutral, count: 8))

    init(channels: [SelectiveColorChannel]) {
        if channels.count == 8 {
            self.channels = channels
        } else {
            self.channels = Array(repeating: .neutral, count: 8)
        }
    }
}

/// Réglages de développement non destructifs (sérialisés dans `PhotoRecord`).
/// Structure inspirée des panneaux « Réglages des couleurs » type Pixelmator Pro.
struct DevelopSettings: Equatable, Sendable {
    // MARK: Réglages de base (existants)

    var brightness: Double
    var exposureEV: Double
    var contrast: Double
    var saturation: Double
    var vibrance: Double
    var highlights: Double
    var shadows: Double
    var temperature: Double
    var tint: Double
    var tslHue: Double
    var tslSaturation: Double
    var tslLuminance: Double
    var clarity: Double
    var texture: Double
    var lensCorrection: Double
    var chromaticAberration: Double
    var maskRadialBlend: Double

    // MARK: Activation par carte (style Pixelmator)

    var enableWhiteBalance: Bool
    var enableBasicAdjustments: Bool
    var enableHueSaturation: Bool
    var enableDetailAdjustments: Bool
    var enableSelectiveClarity: Bool
    var enableSelectiveColor: Bool
    var enableColorBalance: Bool
    var enableLevels: Bool
    var enableCurves: Bool
    var enableRemoveColor: Bool
    var enableBlackWhite: Bool
    var enableLUT: Bool
    var enableVignetting: Bool
    var enableSharpness: Bool
    var enableGrain: Bool
    var enableLensCorrection: Bool
    var enableMasks: Bool

    // MARK: Basique — point noir

    /// −100…100 : assombrit les zones très sombres (type « Point noir »).
    var blackPoint: Double

    // MARK: Clarté sélective — tonalité dominante

    /// 0 = ombres, 1 = tons moyens, 2 = hautes lumières (UI segmentée).
    var selectiveClarityTone: Int

    // MARK: Balance des couleurs (3 voies simplifiées en teinte / saturation par tonalité)

    var cbHighlightHue: Double
    var cbHighlightSaturation: Double
    var cbMidtoneHue: Double
    var cbMidtoneSaturation: Double
    var cbShadowHue: Double
    var cbShadowSaturation: Double

    // MARK: Niveaux

    var levelsInputBlack: Double
    var levelsInputWhite: Double
    var levelsMidtone: Double

    // MARK: Courbes (approximation par tension du ton maître)

    var curvesMasterIntensity: Double

    // MARK: Supprimer couleur

    var removeColorHueKey: Double
    var removeColorRange: Double
    var removeColorLumaRange: Double
    var removeColorIntensity: Double

    // MARK: Noir et blanc

    var bwRed: Double
    var bwGreen: Double
    var bwBlue: Double
    var bwTone: Double
    var bwIntensity: Double

    // MARK: LUT

    var lutPresetIndex: Int
    var lutMix: Double

    // MARK: Vignetage (carte dédiée — combinée au masque radial en rendu)

    var vignetteExposureAmount: Double
    var vignetteSoftnessAmount: Double
    var vignetteBlackPointAmount: Double

    // MARK: Netteté / Grain (cartes séparées du détail « Clarté »)

    var sharpnessRadiusPx: Double
    var sharpnessAmountPct: Double
    var grainSizePct: Double
    var grainIntensityPct: Double

    // MARK: Couleur sélective

    var selectivePalette: SelectiveColorPalette

    static let neutral = DevelopSettings(
        brightness: 0,
        exposureEV: 0,
        contrast: 0,
        saturation: 0,
        vibrance: 0,
        highlights: 0,
        shadows: 0,
        temperature: 0,
        tint: 0,
        tslHue: 0,
        tslSaturation: 0,
        tslLuminance: 0,
        clarity: 0,
        texture: 0,
        lensCorrection: 0,
        chromaticAberration: 0,
        maskRadialBlend: 0,
        enableWhiteBalance: true,
        enableBasicAdjustments: true,
        enableHueSaturation: true,
        enableDetailAdjustments: true,
        enableSelectiveClarity: false,
        enableSelectiveColor: false,
        enableColorBalance: false,
        enableLevels: false,
        enableCurves: false,
        enableRemoveColor: false,
        enableBlackWhite: false,
        enableLUT: false,
        enableVignetting: true,
        enableSharpness: true,
        enableGrain: true,
        enableLensCorrection: true,
        enableMasks: true,
        blackPoint: 0,
        selectiveClarityTone: 1,
        cbHighlightHue: 0,
        cbHighlightSaturation: 0,
        cbMidtoneHue: 0,
        cbMidtoneSaturation: 0,
        cbShadowHue: 0,
        cbShadowSaturation: 0,
        levelsInputBlack: 0,
        levelsInputWhite: 100,
        levelsMidtone: 50,
        curvesMasterIntensity: 0,
        removeColorHueKey: 120,
        removeColorRange: 50,
        removeColorLumaRange: 25,
        removeColorIntensity: 100,
        bwRed: 0,
        bwGreen: 0,
        bwBlue: 0,
        bwTone: 0,
        bwIntensity: 100,
        lutPresetIndex: 0,
        lutMix: 100,
        vignetteExposureAmount: 0,
        vignetteSoftnessAmount: 100,
        vignetteBlackPointAmount: 0,
        sharpnessRadiusPx: 2.5,
        sharpnessAmountPct: 50,
        grainSizePct: 25,
        grainIntensityPct: 50,
        selectivePalette: .neutral
    )

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decode(from data: Data) -> DevelopSettings {
        if let full = try? JSONDecoder().decode(DevelopSettings.self, from: data) {
            return full
        }
        return legacyDecode(from: data)
    }

    private static func legacyDecode(from data: Data) -> DevelopSettings {
        struct Legacy: Codable {
            var exposureEV: Double
            var contrast: Double
            var saturation: Double
            var vibrance: Double
            var highlights: Double
            var shadows: Double
            var temperature: Double
            var tint: Double
            var clarity: Double
            var texture: Double
            var lensCorrection: Double
            var chromaticAberration: Double
        }
        guard let old = try? JSONDecoder().decode(Legacy.self, from: data) else {
            return .neutral
        }
        var n = DevelopSettings.neutral
        n.exposureEV = old.exposureEV
        n.contrast = old.contrast
        n.saturation = old.saturation
        n.vibrance = old.vibrance
        n.highlights = old.highlights
        n.shadows = old.shadows
        n.temperature = old.temperature
        n.tint = old.tint
        n.clarity = old.clarity
        n.texture = old.texture
        n.lensCorrection = old.lensCorrection
        n.chromaticAberration = old.chromaticAberration
        return n
    }

    static var neutralEncodedData: Data {
        (try? neutral.encoded()) ?? Data()
    }
}

extension DevelopSettings: Codable {
    enum CodingKeys: String, CodingKey {
        case brightness, exposureEV, contrast, saturation, vibrance
        case highlights, shadows, temperature, tint
        case tslHue, tslSaturation, tslLuminance
        case clarity, texture, lensCorrection, chromaticAberration, maskRadialBlend
        case enableWhiteBalance, enableBasicAdjustments, enableHueSaturation, enableDetailAdjustments
        case enableSelectiveClarity, enableSelectiveColor, enableColorBalance, enableLevels
        case enableCurves, enableRemoveColor, enableBlackWhite, enableLUT
        case enableVignetting, enableSharpness, enableGrain, enableLensCorrection, enableMasks
        case blackPoint, selectiveClarityTone
        case cbHighlightHue, cbHighlightSaturation, cbMidtoneHue, cbMidtoneSaturation
        case cbShadowHue, cbShadowSaturation
        case levelsInputBlack, levelsInputWhite, levelsMidtone
        case curvesMasterIntensity
        case removeColorHueKey, removeColorRange, removeColorLumaRange, removeColorIntensity
        case bwRed, bwGreen, bwBlue, bwTone, bwIntensity
        case lutPresetIndex, lutMix
        case vignetteExposureAmount, vignetteSoftnessAmount, vignetteBlackPointAmount
        case sharpnessRadiusPx, sharpnessAmountPct, grainSizePct, grainIntensityPct
        case selectivePalette
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var base = DevelopSettings.neutral
        base.brightness = try c.decodeIfPresent(Double.self, forKey: .brightness) ?? 0
        base.exposureEV = try c.decodeIfPresent(Double.self, forKey: .exposureEV) ?? 0
        base.contrast = try c.decodeIfPresent(Double.self, forKey: .contrast) ?? 0
        base.saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 0
        base.vibrance = try c.decodeIfPresent(Double.self, forKey: .vibrance) ?? 0
        base.highlights = try c.decodeIfPresent(Double.self, forKey: .highlights) ?? 0
        base.shadows = try c.decodeIfPresent(Double.self, forKey: .shadows) ?? 0
        base.temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0
        base.tint = try c.decodeIfPresent(Double.self, forKey: .tint) ?? 0
        base.tslHue = try c.decodeIfPresent(Double.self, forKey: .tslHue) ?? 0
        base.tslSaturation = try c.decodeIfPresent(Double.self, forKey: .tslSaturation) ?? 0
        base.tslLuminance = try c.decodeIfPresent(Double.self, forKey: .tslLuminance) ?? 0
        base.clarity = try c.decodeIfPresent(Double.self, forKey: .clarity) ?? 0
        base.texture = try c.decodeIfPresent(Double.self, forKey: .texture) ?? 0
        base.lensCorrection = try c.decodeIfPresent(Double.self, forKey: .lensCorrection) ?? 0
        base.chromaticAberration = try c.decodeIfPresent(Double.self, forKey: .chromaticAberration) ?? 0
        base.maskRadialBlend = try c.decodeIfPresent(Double.self, forKey: .maskRadialBlend) ?? 0

        base.enableWhiteBalance = try c.decodeIfPresent(Bool.self, forKey: .enableWhiteBalance) ?? true
        base.enableBasicAdjustments = try c.decodeIfPresent(Bool.self, forKey: .enableBasicAdjustments) ?? true
        base.enableHueSaturation = try c.decodeIfPresent(Bool.self, forKey: .enableHueSaturation) ?? true
        base.enableDetailAdjustments = try c.decodeIfPresent(Bool.self, forKey: .enableDetailAdjustments) ?? true
        base.enableSelectiveClarity = try c.decodeIfPresent(Bool.self, forKey: .enableSelectiveClarity) ?? false
        base.enableSelectiveColor = try c.decodeIfPresent(Bool.self, forKey: .enableSelectiveColor) ?? false
        base.enableColorBalance = try c.decodeIfPresent(Bool.self, forKey: .enableColorBalance) ?? false
        base.enableLevels = try c.decodeIfPresent(Bool.self, forKey: .enableLevels) ?? false
        base.enableCurves = try c.decodeIfPresent(Bool.self, forKey: .enableCurves) ?? false
        base.enableRemoveColor = try c.decodeIfPresent(Bool.self, forKey: .enableRemoveColor) ?? false
        base.enableBlackWhite = try c.decodeIfPresent(Bool.self, forKey: .enableBlackWhite) ?? false
        base.enableLUT = try c.decodeIfPresent(Bool.self, forKey: .enableLUT) ?? false
        base.enableVignetting = try c.decodeIfPresent(Bool.self, forKey: .enableVignetting) ?? true
        base.enableSharpness = try c.decodeIfPresent(Bool.self, forKey: .enableSharpness) ?? true
        base.enableGrain = try c.decodeIfPresent(Bool.self, forKey: .enableGrain) ?? true
        base.enableLensCorrection = try c.decodeIfPresent(Bool.self, forKey: .enableLensCorrection) ?? true
        base.enableMasks = try c.decodeIfPresent(Bool.self, forKey: .enableMasks) ?? true

        base.blackPoint = try c.decodeIfPresent(Double.self, forKey: .blackPoint) ?? 0
        base.selectiveClarityTone = try c.decodeIfPresent(Int.self, forKey: .selectiveClarityTone) ?? 1

        base.cbHighlightHue = try c.decodeIfPresent(Double.self, forKey: .cbHighlightHue) ?? 0
        base.cbHighlightSaturation = try c.decodeIfPresent(Double.self, forKey: .cbHighlightSaturation) ?? 0
        base.cbMidtoneHue = try c.decodeIfPresent(Double.self, forKey: .cbMidtoneHue) ?? 0
        base.cbMidtoneSaturation = try c.decodeIfPresent(Double.self, forKey: .cbMidtoneSaturation) ?? 0
        base.cbShadowHue = try c.decodeIfPresent(Double.self, forKey: .cbShadowHue) ?? 0
        base.cbShadowSaturation = try c.decodeIfPresent(Double.self, forKey: .cbShadowSaturation) ?? 0

        base.levelsInputBlack = try c.decodeIfPresent(Double.self, forKey: .levelsInputBlack) ?? 0
        base.levelsInputWhite = try c.decodeIfPresent(Double.self, forKey: .levelsInputWhite) ?? 100
        base.levelsMidtone = try c.decodeIfPresent(Double.self, forKey: .levelsMidtone) ?? 50

        base.curvesMasterIntensity = try c.decodeIfPresent(Double.self, forKey: .curvesMasterIntensity) ?? 0

        base.removeColorHueKey = try c.decodeIfPresent(Double.self, forKey: .removeColorHueKey) ?? 120
        base.removeColorRange = try c.decodeIfPresent(Double.self, forKey: .removeColorRange) ?? 50
        base.removeColorLumaRange = try c.decodeIfPresent(Double.self, forKey: .removeColorLumaRange) ?? 25
        base.removeColorIntensity = try c.decodeIfPresent(Double.self, forKey: .removeColorIntensity) ?? 100

        base.bwRed = try c.decodeIfPresent(Double.self, forKey: .bwRed) ?? 0
        base.bwGreen = try c.decodeIfPresent(Double.self, forKey: .bwGreen) ?? 0
        base.bwBlue = try c.decodeIfPresent(Double.self, forKey: .bwBlue) ?? 0
        base.bwTone = try c.decodeIfPresent(Double.self, forKey: .bwTone) ?? 0
        base.bwIntensity = try c.decodeIfPresent(Double.self, forKey: .bwIntensity) ?? 100

        base.lutPresetIndex = try c.decodeIfPresent(Int.self, forKey: .lutPresetIndex) ?? 0
        base.lutMix = try c.decodeIfPresent(Double.self, forKey: .lutMix) ?? 100

        base.vignetteExposureAmount = try c.decodeIfPresent(Double.self, forKey: .vignetteExposureAmount) ?? 0
        base.vignetteSoftnessAmount = try c.decodeIfPresent(Double.self, forKey: .vignetteSoftnessAmount) ?? 100
        base.vignetteBlackPointAmount = try c.decodeIfPresent(Double.self, forKey: .vignetteBlackPointAmount) ?? 0

        base.sharpnessRadiusPx = try c.decodeIfPresent(Double.self, forKey: .sharpnessRadiusPx) ?? 2.5
        base.sharpnessAmountPct = try c.decodeIfPresent(Double.self, forKey: .sharpnessAmountPct) ?? 50
        base.grainSizePct = try c.decodeIfPresent(Double.self, forKey: .grainSizePct) ?? 25
        base.grainIntensityPct = try c.decodeIfPresent(Double.self, forKey: .grainIntensityPct) ?? 50

        base.selectivePalette = try c.decodeIfPresent(SelectiveColorPalette.self, forKey: .selectivePalette) ?? .neutral
        self = base
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(brightness, forKey: .brightness)
        try c.encode(exposureEV, forKey: .exposureEV)
        try c.encode(contrast, forKey: .contrast)
        try c.encode(saturation, forKey: .saturation)
        try c.encode(vibrance, forKey: .vibrance)
        try c.encode(highlights, forKey: .highlights)
        try c.encode(shadows, forKey: .shadows)
        try c.encode(temperature, forKey: .temperature)
        try c.encode(tint, forKey: .tint)
        try c.encode(tslHue, forKey: .tslHue)
        try c.encode(tslSaturation, forKey: .tslSaturation)
        try c.encode(tslLuminance, forKey: .tslLuminance)
        try c.encode(clarity, forKey: .clarity)
        try c.encode(texture, forKey: .texture)
        try c.encode(lensCorrection, forKey: .lensCorrection)
        try c.encode(chromaticAberration, forKey: .chromaticAberration)
        try c.encode(maskRadialBlend, forKey: .maskRadialBlend)
        try c.encode(enableWhiteBalance, forKey: .enableWhiteBalance)
        try c.encode(enableBasicAdjustments, forKey: .enableBasicAdjustments)
        try c.encode(enableHueSaturation, forKey: .enableHueSaturation)
        try c.encode(enableDetailAdjustments, forKey: .enableDetailAdjustments)
        try c.encode(enableSelectiveClarity, forKey: .enableSelectiveClarity)
        try c.encode(enableSelectiveColor, forKey: .enableSelectiveColor)
        try c.encode(enableColorBalance, forKey: .enableColorBalance)
        try c.encode(enableLevels, forKey: .enableLevels)
        try c.encode(enableCurves, forKey: .enableCurves)
        try c.encode(enableRemoveColor, forKey: .enableRemoveColor)
        try c.encode(enableBlackWhite, forKey: .enableBlackWhite)
        try c.encode(enableLUT, forKey: .enableLUT)
        try c.encode(enableVignetting, forKey: .enableVignetting)
        try c.encode(enableSharpness, forKey: .enableSharpness)
        try c.encode(enableGrain, forKey: .enableGrain)
        try c.encode(enableLensCorrection, forKey: .enableLensCorrection)
        try c.encode(enableMasks, forKey: .enableMasks)
        try c.encode(blackPoint, forKey: .blackPoint)
        try c.encode(selectiveClarityTone, forKey: .selectiveClarityTone)
        try c.encode(cbHighlightHue, forKey: .cbHighlightHue)
        try c.encode(cbHighlightSaturation, forKey: .cbHighlightSaturation)
        try c.encode(cbMidtoneHue, forKey: .cbMidtoneHue)
        try c.encode(cbMidtoneSaturation, forKey: .cbMidtoneSaturation)
        try c.encode(cbShadowHue, forKey: .cbShadowHue)
        try c.encode(cbShadowSaturation, forKey: .cbShadowSaturation)
        try c.encode(levelsInputBlack, forKey: .levelsInputBlack)
        try c.encode(levelsInputWhite, forKey: .levelsInputWhite)
        try c.encode(levelsMidtone, forKey: .levelsMidtone)
        try c.encode(curvesMasterIntensity, forKey: .curvesMasterIntensity)
        try c.encode(removeColorHueKey, forKey: .removeColorHueKey)
        try c.encode(removeColorRange, forKey: .removeColorRange)
        try c.encode(removeColorLumaRange, forKey: .removeColorLumaRange)
        try c.encode(removeColorIntensity, forKey: .removeColorIntensity)
        try c.encode(bwRed, forKey: .bwRed)
        try c.encode(bwGreen, forKey: .bwGreen)
        try c.encode(bwBlue, forKey: .bwBlue)
        try c.encode(bwTone, forKey: .bwTone)
        try c.encode(bwIntensity, forKey: .bwIntensity)
        try c.encode(lutPresetIndex, forKey: .lutPresetIndex)
        try c.encode(lutMix, forKey: .lutMix)
        try c.encode(vignetteExposureAmount, forKey: .vignetteExposureAmount)
        try c.encode(vignetteSoftnessAmount, forKey: .vignetteSoftnessAmount)
        try c.encode(vignetteBlackPointAmount, forKey: .vignetteBlackPointAmount)
        try c.encode(sharpnessRadiusPx, forKey: .sharpnessRadiusPx)
        try c.encode(sharpnessAmountPct, forKey: .sharpnessAmountPct)
        try c.encode(grainSizePct, forKey: .grainSizePct)
        try c.encode(grainIntensityPct, forKey: .grainIntensityPct)
        try c.encode(selectivePalette, forKey: .selectivePalette)
    }
}
