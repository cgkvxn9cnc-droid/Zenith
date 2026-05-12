//
//  DevelopSettings.swift
//  Zenith
//

import Foundation

// MARK: - Couleur sélective (8 teintes type référence Pixelmator)

nonisolated struct SelectiveColorChannel: Codable, Equatable, Sendable {
    var hue: Double
    var saturation: Double
    var luminance: Double

    static let neutral = SelectiveColorChannel(hue: 0, saturation: 0, luminance: 0)
}

nonisolated struct SelectiveColorPalette: Codable, Equatable, Sendable {
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
nonisolated struct DevelopSettings: Equatable, Sendable {
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

    /// Recadrage relatif (0…~0,49 par bord) ; tous à 0 = image entière.
    var cropLeft: Double
    var cropTop: Double
    var cropRight: Double
    var cropBottom: Double

    /// Rectangle normalisé (origine **bas‑gauche**, comme Core Image) dans la toile après rotation / retournements : indépendant de la résolution d’export.
    var cropNormalizedOriginX: Double
    var cropNormalizedOriginY: Double
    var cropNormalizedWidth: Double
    var cropNormalizedHeight: Double
    var cropFlipHorizontal: Bool
    var cropFlipVertical: Bool

    /// Proportion de recadrage sélectionnée dans la barre d’outils (`DevelopCropAspectPreset.rawValue`).
    var cropAspectPresetRaw: String

    /// Redressement de l'horizon en degrés (−45…+45, neutre = 0).
    var straightenAngle: Double

    /// Retouche locale : centre normalisé ; désactivé si `healNormX` est négatif ou `healRadiusPx` ≤ 0.
    var healNormX: Double
    var healNormY: Double
    var healRadiusPx: Double

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

    /// −100…100 : comme Lightroom — positif assombrit les noirs (profondeur), négatif les éclaircit (aspect lavé).
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

    // MARK: Courbes (points par canal ; migration JSON depuis `curves*Intensity`)

    var toneCurveMaster: ToneCurve
    var toneCurveRed: ToneCurve
    var toneCurveGreen: ToneCurve
    var toneCurveBlue: ToneCurve

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
    //
    // Champs persistés pour futurs presets / cubes 3D ; **non appliqués** dans `DevelopPreviewRenderer`
    // tant qu’un chargeur LUT n’est pas branché (pas d’UI correspondante pour l’instant).

    var lutPresetIndex: Int
    var lutMix: Double

    // MARK: Vignetage (carte dédiée — combinée au masque radial en rendu)

    var vignetteExposureAmount: Double
    var vignetteSoftnessAmount: Double
    var vignetteBlackPointAmount: Double

    // MARK: TSL par couleur (8 teintes : Rouge, Orange, Jaune, Vert, Cyan, Bleu, Violet, Magenta)

    var enableTSLPerColor: Bool
    var tslPerColorPalette: SelectiveColorPalette

    // MARK: Réduction de bruit

    var enableNoiseReduction: Bool
    var noiseReductionLuminance: Double
    var noiseReductionChrominance: Double

    // MARK: Netteté / Grain (cartes séparées du détail « Clarté »)

    // MARK: Netteté — trois bandes USM RVB (voir `DevelopProSharpening`)

    /// Rayon principal ≈ bande « contours » ; les rayons structure et détail sont dérivés pour les trois passes.
    var sharpnessRadiusPx: Double
    /// Intensité globale des trois passes USM (structure / contours / détail linéaire).
    var sharpnessAmountPct: Double
    /// Répartition détail vs structure + seuillage anti‑grain fin (curseur « Détail »).
    var sharpnessDetailPct: Double
    /// Masque Sobel : protège les aplats (comme « Masquage » Lightroom).
    var sharpnessMaskingPct: Double
    var grainSizePct: Double
    var grainIntensityPct: Double
    /// Irrégularité du grain (mélange texture fine vs plus grossière).
    var grainRoughnessPct: Double

    // MARK: Couleur sélective

    var selectivePalette: SelectiveColorPalette

    // MARK: Tone mapping sigmoïde (inspiration darktable iop/sigmoid.c)
    //
    // Compression dynamique scene-referred → display-referred avec une courbe sigmoïde
    // paramétrique. Donne aux images un rendu plus « photographique » (rolloff naturel
    // sur les hautes lumières, ombres préservées) au lieu du rendu « clipping numérique ».

    var enableToneMapping: Bool
    /// Pente de la sigmoïde au point d'inflexion (1,0 = neutre, 1,5 = contraste cinéma, 0,7 = doux).
    var toneMappingContrast: Double
    /// EV cible pour le « gris moyen » (point pivot ; 0 EV = standard 18 % gris).
    var toneMappingPivotEV: Double
    /// Point blanc relatif (1,0 = 100 % display, 0,9 = compression supplémentaire des hautes lumières).
    var toneMappingWhitePoint: Double

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
        cropLeft: 0,
        cropTop: 0,
        cropRight: 0,
        cropBottom: 0,
        cropNormalizedOriginX: 0,
        cropNormalizedOriginY: 0,
        cropNormalizedWidth: 1,
        cropNormalizedHeight: 1,
        cropFlipHorizontal: false,
        cropFlipVertical: false,
        cropAspectPresetRaw: DevelopCropAspectPreset.free.rawValue,
        straightenAngle: 0,
        healNormX: -1,
        healNormY: -1,
        healRadiusPx: 0,
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
        enableVignetting: false,
        enableSharpness: false,
        enableGrain: false,
        enableLensCorrection: false,
        enableMasks: false,
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
        toneCurveMaster: .identity,
        toneCurveRed: .identity,
        toneCurveGreen: .identity,
        toneCurveBlue: .identity,
        removeColorHueKey: 120,
        removeColorRange: 50,
        removeColorLumaRange: 25,
        removeColorIntensity: 100,
        bwRed: 0,
        bwGreen: 0,
        bwBlue: 0,
        bwTone: 0,
        bwIntensity: 0,
        lutPresetIndex: 0,
        lutMix: 100,
        vignetteExposureAmount: 0,
        vignetteSoftnessAmount: 100,
        vignetteBlackPointAmount: 0,
        enableTSLPerColor: false,
        tslPerColorPalette: .neutral,
        enableNoiseReduction: false,
        noiseReductionLuminance: 0,
        noiseReductionChrominance: 0,
        sharpnessRadiusPx: 2.0,
        sharpnessAmountPct: 0,
        sharpnessDetailPct: 50,
        sharpnessMaskingPct: 0,
        grainSizePct: 25,
        grainIntensityPct: 0,
        grainRoughnessPct: 45,
        selectivePalette: .neutral,
        enableToneMapping: false,
        toneMappingContrast: 1.0,
        toneMappingPivotEV: 0,
        toneMappingWhitePoint: 1.0
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

nonisolated extension DevelopSettings: Codable {
    enum CodingKeys: String, CodingKey {
        case brightness, exposureEV, contrast, saturation, vibrance
        case highlights, shadows, temperature, tint
        case tslHue, tslSaturation, tslLuminance
        case clarity, texture, lensCorrection, chromaticAberration, maskRadialBlend
        case cropLeft, cropTop, cropRight, cropBottom
        case cropNormalizedOriginX, cropNormalizedOriginY, cropNormalizedWidth, cropNormalizedHeight
        case cropFlipHorizontal, cropFlipVertical
        case cropAspectPresetRaw
        case straightenAngle
        case healNormX, healNormY, healRadiusPx
        case enableWhiteBalance, enableBasicAdjustments, enableHueSaturation, enableDetailAdjustments
        case enableSelectiveClarity, enableSelectiveColor, enableColorBalance, enableLevels
        case enableCurves, enableRemoveColor, enableBlackWhite, enableLUT
        case enableVignetting, enableSharpness, enableGrain, enableLensCorrection, enableMasks
        case blackPoint, selectiveClarityTone
        case cbHighlightHue, cbHighlightSaturation, cbMidtoneHue, cbMidtoneSaturation
        case cbShadowHue, cbShadowSaturation
        case levelsInputBlack, levelsInputWhite, levelsMidtone
        case toneCurveMaster, toneCurveRed, toneCurveGreen, toneCurveBlue
        case curvesMasterIntensity, curvesRedIntensity, curvesGreenIntensity, curvesBlueIntensity
        case removeColorHueKey, removeColorRange, removeColorLumaRange, removeColorIntensity
        case enableTSLPerColor, tslPerColorPalette
        case enableNoiseReduction, noiseReductionLuminance, noiseReductionChrominance
        case bwRed, bwGreen, bwBlue, bwTone, bwIntensity
        case lutPresetIndex, lutMix
        case vignetteExposureAmount, vignetteSoftnessAmount, vignetteBlackPointAmount
        case sharpnessRadiusPx, sharpnessAmountPct, sharpnessDetailPct, sharpnessMaskingPct, grainSizePct, grainIntensityPct, grainRoughnessPct
        case selectivePalette
        case enableToneMapping, toneMappingContrast, toneMappingPivotEV, toneMappingWhitePoint
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

        base.cropLeft = try c.decodeIfPresent(Double.self, forKey: .cropLeft) ?? 0
        base.cropTop = try c.decodeIfPresent(Double.self, forKey: .cropTop) ?? 0
        base.cropRight = try c.decodeIfPresent(Double.self, forKey: .cropRight) ?? 0
        base.cropBottom = try c.decodeIfPresent(Double.self, forKey: .cropBottom) ?? 0

        if let nx = try c.decodeIfPresent(Double.self, forKey: .cropNormalizedOriginX),
           let ny = try c.decodeIfPresent(Double.self, forKey: .cropNormalizedOriginY),
           let nw = try c.decodeIfPresent(Double.self, forKey: .cropNormalizedWidth),
           let nh = try c.decodeIfPresent(Double.self, forKey: .cropNormalizedHeight) {
            base.cropNormalizedOriginX = nx
            base.cropNormalizedOriginY = ny
            base.cropNormalizedWidth = nw
            base.cropNormalizedHeight = nh
        } else {
            DevelopCropGeometry.migrateNormalizedCropFromLegacyMargins(&base)
        }
        base.cropFlipHorizontal = try c.decodeIfPresent(Bool.self, forKey: .cropFlipHorizontal) ?? false
        base.cropFlipVertical = try c.decodeIfPresent(Bool.self, forKey: .cropFlipVertical) ?? false

        base.cropAspectPresetRaw = try c.decodeIfPresent(String.self, forKey: .cropAspectPresetRaw) ?? DevelopCropAspectPreset.free.rawValue
        base.straightenAngle = try c.decodeIfPresent(Double.self, forKey: .straightenAngle) ?? 0
        base.healNormX = try c.decodeIfPresent(Double.self, forKey: .healNormX) ?? -1
        base.healNormY = try c.decodeIfPresent(Double.self, forKey: .healNormY) ?? -1
        base.healRadiusPx = try c.decodeIfPresent(Double.self, forKey: .healRadiusPx) ?? 0

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

        if let m = try c.decodeIfPresent(ToneCurve.self, forKey: .toneCurveMaster) {
            base.toneCurveMaster = m
        } else {
            let leg = try c.decodeIfPresent(Double.self, forKey: .curvesMasterIntensity) ?? 0
            base.toneCurveMaster = ToneCurve.legacyMaster(fromIntensityPercent: leg)
        }
        if let r = try c.decodeIfPresent(ToneCurve.self, forKey: .toneCurveRed) {
            base.toneCurveRed = r
        } else {
            let leg = try c.decodeIfPresent(Double.self, forKey: .curvesRedIntensity) ?? 0
            base.toneCurveRed = ToneCurve.legacyChannel(fromIntensityPercent: leg)
        }
        if let g = try c.decodeIfPresent(ToneCurve.self, forKey: .toneCurveGreen) {
            base.toneCurveGreen = g
        } else {
            let leg = try c.decodeIfPresent(Double.self, forKey: .curvesGreenIntensity) ?? 0
            base.toneCurveGreen = ToneCurve.legacyChannel(fromIntensityPercent: leg)
        }
        if let b = try c.decodeIfPresent(ToneCurve.self, forKey: .toneCurveBlue) {
            base.toneCurveBlue = b
        } else {
            let leg = try c.decodeIfPresent(Double.self, forKey: .curvesBlueIntensity) ?? 0
            base.toneCurveBlue = ToneCurve.legacyChannel(fromIntensityPercent: leg)
        }

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

        base.sharpnessRadiusPx = try c.decodeIfPresent(Double.self, forKey: .sharpnessRadiusPx) ?? 2.0
        base.sharpnessAmountPct = try c.decodeIfPresent(Double.self, forKey: .sharpnessAmountPct) ?? 42
        base.sharpnessDetailPct = try c.decodeIfPresent(Double.self, forKey: .sharpnessDetailPct) ?? 48
        base.sharpnessMaskingPct = try c.decodeIfPresent(Double.self, forKey: .sharpnessMaskingPct) ?? 14
        base.grainSizePct = try c.decodeIfPresent(Double.self, forKey: .grainSizePct) ?? 25
        base.grainIntensityPct = try c.decodeIfPresent(Double.self, forKey: .grainIntensityPct) ?? 50
        base.grainRoughnessPct = try c.decodeIfPresent(Double.self, forKey: .grainRoughnessPct) ?? 45

        base.selectivePalette = try c.decodeIfPresent(SelectiveColorPalette.self, forKey: .selectivePalette) ?? .neutral

        base.enableTSLPerColor = try c.decodeIfPresent(Bool.self, forKey: .enableTSLPerColor) ?? false
        base.tslPerColorPalette = try c.decodeIfPresent(SelectiveColorPalette.self, forKey: .tslPerColorPalette) ?? .neutral

        base.enableNoiseReduction = try c.decodeIfPresent(Bool.self, forKey: .enableNoiseReduction) ?? false
        base.noiseReductionLuminance = try c.decodeIfPresent(Double.self, forKey: .noiseReductionLuminance) ?? 0
        base.noiseReductionChrominance = try c.decodeIfPresent(Double.self, forKey: .noiseReductionChrominance) ?? 0

        base.enableToneMapping = try c.decodeIfPresent(Bool.self, forKey: .enableToneMapping) ?? false
        base.toneMappingContrast = try c.decodeIfPresent(Double.self, forKey: .toneMappingContrast) ?? 1.0
        base.toneMappingPivotEV = try c.decodeIfPresent(Double.self, forKey: .toneMappingPivotEV) ?? 0
        base.toneMappingWhitePoint = try c.decodeIfPresent(Double.self, forKey: .toneMappingWhitePoint) ?? 1.0

        if base.straightenAngle.isFinite {
            base.straightenAngle = max(-45, min(45, base.straightenAngle))
        } else {
            base.straightenAngle = 0
        }

        DevelopCropGeometry.clampNormalizedCrop(in: &base)
        DevelopCropGeometry.syncLegacyMarginsFromNormalized(&base)

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
        try c.encode(cropLeft, forKey: .cropLeft)
        try c.encode(cropTop, forKey: .cropTop)
        try c.encode(cropRight, forKey: .cropRight)
        try c.encode(cropBottom, forKey: .cropBottom)
        try c.encode(cropNormalizedOriginX, forKey: .cropNormalizedOriginX)
        try c.encode(cropNormalizedOriginY, forKey: .cropNormalizedOriginY)
        try c.encode(cropNormalizedWidth, forKey: .cropNormalizedWidth)
        try c.encode(cropNormalizedHeight, forKey: .cropNormalizedHeight)
        try c.encode(cropFlipHorizontal, forKey: .cropFlipHorizontal)
        try c.encode(cropFlipVertical, forKey: .cropFlipVertical)
        try c.encode(cropAspectPresetRaw, forKey: .cropAspectPresetRaw)
        try c.encode(straightenAngle, forKey: .straightenAngle)
        try c.encode(healNormX, forKey: .healNormX)
        try c.encode(healNormY, forKey: .healNormY)
        try c.encode(healRadiusPx, forKey: .healRadiusPx)
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
        try c.encode(toneCurveMaster, forKey: .toneCurveMaster)
        try c.encode(toneCurveRed, forKey: .toneCurveRed)
        try c.encode(toneCurveGreen, forKey: .toneCurveGreen)
        try c.encode(toneCurveBlue, forKey: .toneCurveBlue)
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
        try c.encode(sharpnessDetailPct, forKey: .sharpnessDetailPct)
        try c.encode(sharpnessMaskingPct, forKey: .sharpnessMaskingPct)
        try c.encode(grainSizePct, forKey: .grainSizePct)
        try c.encode(grainIntensityPct, forKey: .grainIntensityPct)
        try c.encode(grainRoughnessPct, forKey: .grainRoughnessPct)
        try c.encode(selectivePalette, forKey: .selectivePalette)
        try c.encode(enableTSLPerColor, forKey: .enableTSLPerColor)
        try c.encode(tslPerColorPalette, forKey: .tslPerColorPalette)
        try c.encode(enableNoiseReduction, forKey: .enableNoiseReduction)
        try c.encode(noiseReductionLuminance, forKey: .noiseReductionLuminance)
        try c.encode(noiseReductionChrominance, forKey: .noiseReductionChrominance)

        try c.encode(enableToneMapping, forKey: .enableToneMapping)
        try c.encode(toneMappingContrast, forKey: .toneMappingContrast)
        try c.encode(toneMappingPivotEV, forKey: .toneMappingPivotEV)
        try c.encode(toneMappingWhitePoint, forKey: .toneMappingWhitePoint)
    }
}
