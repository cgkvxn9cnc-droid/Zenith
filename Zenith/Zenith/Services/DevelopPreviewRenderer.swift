//
//  DevelopPreviewRenderer.swift
//  Zenith
//

import AppKit
import CoreImage
import ImageIO
import Metal
import UniformTypeIdentifiers

/*
 Parité `DevelopSettings.enable*` ↔ séquence `developedCIImage(from:settings:…)` (aperçu / export partagent ce pipeline) :

 Implémentés (garde `if settings.enable…` dans la chaîne) :
   enableBlackWhite, enableBasicAdjustments, enableHueSaturation, enableTSLPerColor,
   enableWhiteBalance, enableCurves, enableColorBalance, enableNoiseReduction,
   enableSharpness, enableGrain.

 Non branchés ici (pas d’effet ou helpers non invoqués) :
   enableLevels (`applyRGBLevels` non appelé), enableRemoveColor, enableLUT,
   enableSelectiveClarity, enableSelectiveColor,
   enableVignetting / enableMasks (`applyCombinedVignette` non appelé),
   enableLensCorrection (`applyLensDistortion` / aberrations non invoqués),
   enableToneMapping (`applySigmoidToneMapping` non invoqué),
   enableDetailAdjustments (aucune garde : netteté / NR / texture suivent enableSharpness, enableNoiseReduction, enableBasicAdjustments).
 */

/// Pipeline de rendu de l'aperçu Develop.
///
/// Core Image s’exécute sur le GPU via Metal (`CIContext` partagé) : les appels ci‑dessous sont **non isolés**
/// et hors MainActor ; les vues (`PhotoPreviewView`) déportent déjà le rendu dans `Task.detached` avec debounce.
///
/// Inspirations darktable :
/// - **Entrée RAW** : `ZenithImageSourceLoader` utilise `CIRAWFilter` (réponse linéaire côté décodeur, EDR) au lieu d’un simple `CIImage(contentsOf:)`.
/// - **Pipeline scene-referred linéaire** : on travaille en `Linear sRGB` jusqu'à la sortie display.
///   darktable maintient des valeurs flottantes linéaires tout au long de son pipeline iop ; on s'en
///   approche en imposant `workingColorSpace = linearSRGB` au `CIContext`. Ça évite que chaque filtre
///   re-décode sRGB → linéaire → applique → ré-encode sRGB → ce qui est très coûteux.
/// - **Working format half-float (RGBAh)** : darktable utilise des buffers float ; sur Mac Apple Silicon
///   la half-float (16 bits) suffit pour préserver la dynamique sans saturer la VRAM ni le bandwidth.
/// - **GPU explicite** : Metal device dédié, pas de fallback CPU.
nonisolated enum DevelopPreviewRenderer {
    /// Context Metal global, partagé par toutes les passes du pipeline + le rendu final.
    /// Le partager évite de re-créer les caches Metal/MPS à chaque rendu (gain dramatique).
    /// On passe par `NSNumber` pour les booléens et le format pixel : le pont Swift→ObjC peut sinon
    /// passer un `Bool` brut là où Core Image attend explicitement un `NSNumber`, ce qui peut faire
    /// crasher l'init du context sur certaines versions de macOS.
    static let sharedContext: CIContext = {
        var options: [CIContextOption: Any] = [:]
        options[.useSoftwareRenderer] = NSNumber(value: false)
        options[.cacheIntermediates] = NSNumber(value: true)
        options[.workingFormat] = NSNumber(value: CIFormat.RGBAh.rawValue)
        if let workingSpace = CGColorSpace(name: CGColorSpace.linearSRGB) {
            options[.workingColorSpace] = workingSpace
        }
        if let outputSpace = CGColorSpace(name: CGColorSpace.sRGB) {
            options[.outputColorSpace] = outputSpace
        }
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: options)
        }
        return CIContext(options: options)
    }()

    /// Conservé pour compatibilité : alias vers `sharedContext`.
    private static var context: CIContext { sharedContext }

    private static let previewMaxDimension: CGFloat = 4096

    /// Rectangle pixel entier couvrant l’étendue CI. Les bornes flottantes passées à `CIContext.createCGImage(_:from:)`
    /// provoquent fréquemment des artefacts (bandes, tuiles noires) sur le rendu Metal.
    nonisolated static func integralRectForRasterization(_ extent: CGRect) -> CGRect? {
        guard !CGRectIsNull(extent), !CGRectIsInfinite(extent) else { return nil }
        let x = extent.origin.x
        let y = extent.origin.y
        let w = extent.size.width
        let h = extent.size.height
        guard x.isFinite, y.isFinite, w.isFinite, h.isFinite, w > 0, h > 0 else { return nil }
        let x0 = floor(x)
        let y0 = floor(y)
        let x1 = ceil(x + w)
        let y1 = ceil(y + h)
        let iw = x1 - x0
        let ih = y1 - y0
        guard iw > 0, ih > 0, iw.isFinite, ih.isFinite else { return nil }
        return CGRect(x: x0, y: y0, width: iw, height: ih)
    }

    /// CIImage après pipeline développement (même logique que l’aperçu).
    /// - Parameters:
    ///   - applyCrop: `false` pendant l’outil recadrage pour garder les proportions du cadre plein à l’écran.
    ///   - maxSourceDecodeDimension: borne optionnelle du décodage (histogramme, etc.) pour ne pas refaire un 4K à chaque micro-mouvement de curseur.
    nonisolated static func developedCIImage(
        url: URL,
        settings: DevelopSettings,
        applyCrop: Bool = true,
        quality: DevelopPipelineQuality = .high,
        maxSourceDecodeDimension: CGFloat? = nil
    ) -> CIImage? {
        let decodeCap: CGFloat = {
            guard let cap = maxSourceDecodeDimension else { return previewMaxDimension }
            return min(max(256, cap), previewMaxDimension)
        }()
        guard let ci = ZenithImageSourceLoader.ciImage(
            contentsOf: url,
            maxPixelDimension: decodeCap,
            draftMode: false
        ) else { return nil }
        /// RVB/CMJN bitmap : normalisation ICC → espace de travail linéaire. Les RAW ne passent pas par `describeIfBitmap` et restent gérés par `CIRAWFilter`.
        var output = ZenithSourceColorNormalizer.normalizeForDevelopPipeline(image: ci, url: url)
        let maxDim = max(output.extent.width, output.extent.height)
        if maxDim > previewMaxDimension {
            let s = previewMaxDimension / maxDim
            output = output.transformed(by: CGAffineTransform(scaleX: s, y: s))
        }
        return developedCIImage(from: output, settings: settings, applyCrop: applyCrop, quality: quality)
    }

    /// Pipeline appliqué sur une CIImage déjà redimensionnée (utilisé par le cache proxy).
    nonisolated static func developedCIImage(from source: CIImage, settings: DevelopSettings, applyCrop: Bool = true, quality: DevelopPipelineQuality = .high) -> CIImage? {
        var output = source
        if applyCrop {
            output = DevelopCropPipeline.applyOrientAndCrop(to: output, settings: settings)
        } else {
            output = DevelopCropPipeline.applyOrientationOnly(to: output, settings: settings)
        }
        let workExtent = output.extent
        let ww = workExtent.size.width
        let wh = workExtent.size.height
        guard ww.isFinite, wh.isFinite, ww > 0, wh > 0 else {
            return nil
        }

        // 1 — Noir & blanc
        if settings.enableBlackWhite {
            output = applyBlackWhiteMix(output, settings: settings)
        }

        // 2 — Basique : exposition (lumière globale type boîtier), puis contraste ; ombres / hautes lumières / point noir séparés (Lightroom).
        if settings.enableBasicAdjustments {
            let hl = DevelopPipelineColorMath.softenSigned100(settings.highlights, exponent: 1.18)
            let shadowsCombined = combinedShadowAmount(
                sliderShadows: DevelopPipelineColorMath.softenSigned100(settings.shadows, exponent: 1.18),
                blackPoint: DevelopPipelineColorMath.softenSigned100(settings.blackPoint, exponent: 1.16)
            )
            let needsBasic =
                settings.exposureEV != 0
                || settings.brightness != 0
                || settings.contrast != 0
                || settings.highlights != 0
                || settings.shadows != 0
                || settings.blackPoint != 0
            if needsBasic {
                if settings.exposureEV != 0 {
                    let ev = DevelopPipelineColorMath.softenSignedEV(settings.exposureEV, halfRange: 4, exponent: 1.22)
                    output = applyExposure(output, ev: ev)
                }
                if settings.brightness != 0 {
                    let b = DevelopPipelineColorMath.softenSigned100(settings.brightness, exponent: 1.18)
                    output = applyBrightness(output, brightness: b)
                }
                if settings.contrast != 0 {
                    // Contraste volontairement amorti : le curseur doit rester progressif,
                    // même sur des scènes déjà très contrastées.
                    let c = DevelopPipelineColorMath.softenSigned100(settings.contrast, exponent: 1.35) * 0.62
                    output = applyContrast(output, amount: c)
                }
                if hl != 0 || shadowsCombined != 0 {
                    output = applyHighlightShadow(output, highlights: hl, shadows: shadowsCombined)
                }
            }
        }

        // 3 — Teinte / saturation (sans luminance parasite) + vibrance (style Lightroom « Teinte »).
        let hueSatCombined = DevelopPipelineColorMath.softenSigned100(
            settings.tslSaturation + settings.saturation,
            exponent: 1.16
        )
        if settings.enableHueSaturation,
           settings.tslHue != 0 || settings.tslSaturation + settings.saturation != 0 || settings.vibrance != 0 {
            if settings.tslHue != 0 {
                let hue = DevelopPipelineColorMath.softenSigned100(settings.tslHue, exponent: 1.15)
                output = applyHue(output, hueDegrees: hue)
            }
            if settings.tslSaturation + settings.saturation != 0 {
                output = applyColorControls(
                    output,
                    saturationDelta: hueSatCombined,
                    contrastDelta: 0,
                    brightnessDelta: 0
                )
            }
            if settings.vibrance != 0 {
                let v = DevelopPipelineColorMath.softenSigned100(settings.vibrance, exponent: 1.14)
                output = applyVibrance(output, amount: v)
            }
        }

        // 3b — TSL par couleur (Teinte / Saturation / Luminance par teinte, style Lightroom)
        if settings.enableTSLPerColor {
            output = applyTSLPerColor(output, palette: settings.tslPerColorPalette)
        }

        // 4 — Balance des blancs
        if settings.enableWhiteBalance, settings.temperature != 0 || settings.tint != 0 {
            let temp = DevelopPipelineColorMath.softenSigned100(settings.temperature, exponent: 1.12)
            let tint = DevelopPipelineColorMath.softenSigned100(settings.tint, exponent: 1.12)
            output = applyTemperatureTint(output, temperature: temp, tint: tint)
        }

        // 5 — Courbes (LUT PCHIP mise en cache ; maître puis R / V / B).
        if settings.enableCurves {
            let lutBundle = ToneCurveLUTCache.lutBundle(
                master: settings.toneCurveMaster,
                red: settings.toneCurveRed,
                green: settings.toneCurveGreen,
                blue: settings.toneCurveBlue,
                sampleCount: quality.curveLUTSampleCount
            )
            if let masterSamples = lutBundle.master {
                output = applyColorCurves(output, samples: masterSamples)
            }
            if let s = lutBundle.red {
                output = applyToneCurveChannelSamples(output, ySamples: s, channelIndex: 0)
            }
            if let s = lutBundle.green {
                output = applyToneCurveChannelSamples(output, ySamples: s, channelIndex: 1)
            }
            if let s = lutBundle.blue {
                output = applyToneCurveChannelSamples(output, ySamples: s, channelIndex: 2)
            }
        }

        // 6 — Balance des couleurs (trois tons pondérés par la luminance linéaire Rec.709)
        let hasColorBalanceAdjustment =
            settings.cbHighlightHue != 0 || settings.cbHighlightSaturation != 0
            || settings.cbMidtoneHue != 0 || settings.cbMidtoneSaturation != 0
            || settings.cbShadowHue != 0 || settings.cbShadowSaturation != 0
        if settings.enableColorBalance, hasColorBalanceAdjustment {
            output = applyColorBalanceApprox(output, settings: settings)
        }

        // 7 — Clarté puis Texture (Basique) : bandes fréquentielles distinctes, espace linéaire du CIContext.
        //    Clarté : grand flou gaussien → (original − basse fréq.) × masque luminance (mid-tones).
        //    Texture : petit flou → hautes fréq. × gain sur luminance × masque gradient (contours).
        if settings.enableBasicAdjustments {
            // Réponse quasi linéaire : clarté / texture doivent être lisibles sur tout le curseur ±100.
            let clarityAmount = DevelopPipelineColorMath.softenSigned100(settings.clarity, exponent: 1.0)
            if settings.clarity != 0 {
                output = applyClarity(output, amount: clarityAmount)
            }
            if settings.texture != 0 {
                let tex = DevelopPipelineColorMath.softenSigned100(settings.texture, exponent: 1.0)
                output = applyTexture(output, amount: tex, referenceExtent: workExtent)
            }
        }

        // 8 — Réduction de bruit (luminance + chrominance)
        if settings.enableNoiseReduction,
           settings.noiseReductionLuminance > 0 || settings.noiseReductionChrominance > 0 {
            output = applyNoiseReduction(
                output,
                luminance: DevelopPipelineColorMath.softenUnsigned(settings.noiseReductionLuminance, exponent: 1.1),
                chrominance: DevelopPipelineColorMath.softenUnsigned(settings.noiseReductionChrominance, exponent: 1.1)
            )
        }

        // 9 — Netteté
        if settings.enableSharpness, settings.sharpnessAmountPct > 0 {
            output = DevelopProSharpening.apply(output, settings: settings, quality: quality)
        }

        // 10 — Grain
        if settings.enableGrain, settings.grainIntensityPct > 0 {
            output = applyFilmGrain(
                output,
                sizePct: DevelopPipelineColorMath.softenUnsigned(settings.grainSizePct, exponent: 1.06),
                intensityPct: DevelopPipelineColorMath.softenUnsigned(settings.grainIntensityPct, exponent: 1.12),
                roughnessPct: DevelopPipelineColorMath.softenUnsigned(settings.grainRoughnessPct, exponent: 1.06),
                referenceExtent: workExtent
            )
        }

        output = applyHealSpotIfNeeded(output, settings: settings)
        output = output.cropped(to: workExtent)
        return output
    }

    /// Contexte CI dédié export : `highQualityDownsample` pour limiter l’aliasing lors des rotations / réductions.
    private static let exportContext: CIContext = {
        var options: [CIContextOption: Any] = [:]
        options[.highQualityDownsample] = NSNumber(value: true)
        options[.useSoftwareRenderer] = NSNumber(value: false)
        options[.cacheIntermediates] = NSNumber(value: true)
        options[.workingFormat] = NSNumber(value: CIFormat.RGBAh.rawValue)
        if let workingSpace = CGColorSpace(name: CGColorSpace.linearSRGB) {
            options[.workingColorSpace] = workingSpace
        }
        if let outputSpace = CGColorSpace(name: CGColorSpace.sRGB) {
            options[.outputColorSpace] = outputSpace
        }
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: options)
        }
        return CIContext(options: options)
    }()

    /// Flou local (retouche type « pansement ») sur une zone circulaire.
    private static func applyHealSpotIfNeeded(_ input: CIImage, settings: DevelopSettings) -> CIImage {
        guard settings.healRadiusPx > 0.5,
              settings.healNormX >= 0, settings.healNormY >= 0,
              settings.healNormX <= 1, settings.healNormY <= 1 else { return input }
        let e = input.extent
        let cx = e.minX + CGFloat(settings.healNormX) * e.width
        // Repère SwiftUI (Y depuis le haut) → Core Image (origine en bas à gauche).
        let cy = e.maxY - CGFloat(settings.healNormY) * e.height
        let R = min(min(e.width, e.height) * 0.48, max(6, CGFloat(settings.healRadiusPx)))
        let rect = CGRect(x: cx - R, y: cy - R, width: R * 2, height: R * 2).intersection(e)
        guard rect.width > 3, rect.height > 3 else { return input }
        let patchIn = input.cropped(to: rect)
        guard let blur = CIFilter(name: "CIGaussianBlur") else { return input }
        blur.setValue(patchIn, forKey: kCIInputImageKey)
        blur.setValue(min(14, max(1, R / 5)), forKey: kCIInputRadiusKey)
        guard let blurredPatch = blur.outputImage?.cropped(to: rect) else { return input }
        guard let over = CIFilter(name: "CISourceOverCompositing") else { return input }
        over.setValue(blurredPatch, forKey: kCIInputImageKey)
        over.setValue(input, forKey: kCIInputBackgroundImageKey)
        return over.outputImage ?? input
    }

    nonisolated static func render(url: URL, settings: DevelopSettings, applyCrop: Bool = true, quality: DevelopPipelineQuality = .high) -> NSImage? {
        guard let output = developedCIImage(url: url, settings: settings, applyCrop: applyCrop, quality: quality) else {
            return NSImage(contentsOf: url)
        }
        guard let ir = integralRectForRasterization(output.extent) else {
            return NSImage(contentsOf: url)
        }
        guard let cg = ZenithColorRendering.createDevelopPreviewCGImage(context: context, output: output, from: ir)
            ?? context.createCGImage(output, from: ir) else {
            return NSImage(contentsOf: url)
        }
        return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width), height: CGFloat(cg.height)))
    }

    /// Export fichier : même pipeline avec rééchantillonnage haute qualité (rotation / taille).
    nonisolated static func renderForExport(url: URL, settings: DevelopSettings, applyCrop: Bool = true, quality: DevelopPipelineQuality = .high) -> NSImage? {
        guard let output = developedCIImage(url: url, settings: settings, applyCrop: applyCrop, quality: quality) else {
            return NSImage(contentsOf: url)
        }
        guard let ir = integralRectForRasterization(output.extent) else {
            return NSImage(contentsOf: url)
        }
        guard let cg = exportContext.createCGImage(output, from: ir) else {
            return NSImage(contentsOf: url)
        }
        return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width), height: CGFloat(cg.height)))
    }

    // MARK: - Noir & blanc

    /// Mixer RVB façon Lightroom : luminance Σ wᵢ·canalᵢ (Rec.709 + sliders), tonalité optionnelle, mélange `bwIntensity`.
    private static func applyBlackWhiteMix(_ input: CIImage, settings: DevelopSettings) -> CIImage {
        let mixPct = DevelopPipelineColorMath.softenUnsigned(settings.bwIntensity, maxValue: 100, exponent: 1.08)
        let mix = min(1, max(0, mixPct / 100))
        guard mix > 0.01 else { return input }

        let w = DevelopPipelineColorMath.blackWhiteChannelWeights(
            bwRed: DevelopPipelineColorMath.softenSigned100(settings.bwRed, exponent: 1.12),
            bwGreen: DevelopPipelineColorMath.softenSigned100(settings.bwGreen, exponent: 1.12),
            bwBlue: DevelopPipelineColorMath.softenSigned100(settings.bwBlue, exponent: 1.12)
        )

        guard let matrix = CIFilter(name: "CIColorMatrix") else { return input }
        matrix.setValue(input, forKey: kCIInputImageKey)
        let row = CIVector(x: w.wr, y: w.wg, z: w.wb, w: 0)
        matrix.setValue(row, forKey: "inputRVector")
        matrix.setValue(row, forKey: "inputGVector")
        matrix.setValue(row, forKey: "inputBVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        guard var gray = matrix.outputImage else { return input }

        let tone = max(-100, min(100, DevelopPipelineColorMath.softenSigned100(settings.bwTone, exponent: 1.12)))
        if abs(tone) > 0.25, let cc = CIFilter(name: "CIColorControls") {
            cc.setValue(gray, forKey: kCIInputImageKey)
            cc.setValue(0.0, forKey: kCIInputSaturationKey)
            cc.setValue(1.0, forKey: kCIInputContrastKey)
            cc.setValue(tone / 100.0 * 0.42, forKey: kCIInputBrightnessKey)
            gray = cc.outputImage ?? gray
        }

        guard let blend = CIFilter(name: "CIMix") else { return gray }
        blend.setValue(gray, forKey: kCIInputImageKey)
        blend.setValue(input, forKey: kCIInputBackgroundImageKey)
        blend.setValue(mix, forKey: kCIInputAmountKey)
        return blend.outputImage ?? input
    }

    // MARK: - Niveaux (étirement noir/blanc + gamma milieu en domaine codé sRGB, sortie linéaire)

    /// Curseurs 0…100 : référence histogramme **affiché** ; la LUT mappe linéaire → linéaire via l’axe codé.
    private static func applyRGBLevels(_ input: CIImage, settings: DevelopSettings, sampleCount: Int) -> CIImage {
        let samples = DevelopPipelineColorMath.rgbLevelsPerceptualLUT(
            inputBlackPct: settings.levelsInputBlack,
            inputWhitePct: settings.levelsInputWhite,
            midtonePct: settings.levelsMidtone,
            sampleCount: sampleCount
        )
        return applyColorCurves(input, samples: samples)
    }

    /// Helper : applique `CIColorCurves` aux 3 canaux à partir de samples [0,1] uniformes.
    private static func applyColorCurves(_ input: CIImage, samples: [Double]) -> CIImage {
        guard samples.count >= 2,
              let curveData = colorCurvesData(samples: samples),
              let space = CGColorSpace(name: CGColorSpace.linearSRGB) else {
            return input
        }
        return applyColorCurvesCore(input: input, curvesData: curveData, colorSpace: space) ?? input
    }

    /// `CIFilter.colorCurves()` n’existe pas sur toutes les cibles macOS ; on utilise le filtre nommé avec les clés KVC
    /// documentées : `inputCurvesData`, `inputCurvesDomain`, `inputColorSpace` (pas `inputCurvePoints`).
    private static func applyColorCurvesCore(input: CIImage, curvesData: Data, colorSpace: CGColorSpace) -> CIImage? {
        guard let f = CIFilter(name: "CIColorCurves") else { return nil }
        f.setValue(input, forKey: kCIInputImageKey)
        f.setValue(curvesData, forKey: "inputCurvesData")
        f.setValue(CIVector(x: 0, y: 1), forKey: "inputCurvesDomain")
        f.setValue(colorSpace, forKey: kCIInputColorSpaceKey)
        return f.outputImage
    }

    /// Encode les samples [0,1] en `Data` au format attendu par les courbes Core Image :
    /// triplets (R, G, B) en Float32, ici mis en mode greyscale (R = G = B = sample).
    private static func colorCurvesData(samples: [Double]) -> Data? {
        var floats: [Float] = []
        floats.reserveCapacity(samples.count * 3)
        for v in samples {
            let f = Float(min(1.0, max(0.0, v)))
            floats.append(f); floats.append(f); floats.append(f)
        }
        return floats.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return nil }
            return Data(bytes: base, count: ptr.count * MemoryLayout<Float>.size)
        }
    }

    /// Courbe sur un canal à partir d’échantillons PCHIP déjà calculés (cache).
    private nonisolated static func applyToneCurveChannelSamples(_ input: CIImage, ySamples: [Double], channelIndex: Int) -> CIImage {
        let n = ySamples.count
        guard n >= 2 else { return input }
        var r = [Double](repeating: 0, count: n)
        var g = [Double](repeating: 0, count: n)
        var b = [Double](repeating: 0, count: n)
        for j in 0 ..< n {
            let lin = Double(j) / Double(n - 1)
            switch channelIndex {
            case 0:
                r[j] = ySamples[j]
                g[j] = lin
                b[j] = lin
            case 1:
                r[j] = lin
                g[j] = ySamples[j]
                b[j] = lin
            default:
                r[j] = lin
                g[j] = lin
                b[j] = ySamples[j]
            }
        }
        return applyChannelColorCurves(input, r: r, g: g, b: b)
    }

    // MARK: - Balance des couleurs (approximation)

    private static func applyColorBalanceApprox(_ input: CIImage, settings: DevelopSettings) -> CIImage {
        DevelopPreviewKernels.applyColorBalanceThreeWay(
            to: input,
            extent: input.extent,
            shadowHue: DevelopPipelineColorMath.softenSigned100(settings.cbShadowHue, exponent: 1.1),
            midHue: DevelopPipelineColorMath.softenSigned100(settings.cbMidtoneHue, exponent: 1.1),
            highHue: DevelopPipelineColorMath.softenSigned100(settings.cbHighlightHue, exponent: 1.1),
            shadowSat: DevelopPipelineColorMath.softenSigned100(settings.cbShadowSaturation, exponent: 1.1),
            midSat: DevelopPipelineColorMath.softenSigned100(settings.cbMidtoneSaturation, exponent: 1.1),
            highSat: DevelopPipelineColorMath.softenSigned100(settings.cbHighlightSaturation, exponent: 1.1)
        )
    }

    /// Sépare les **fréquences moyennes** (grand rayon gaussien ~40–60 px) et les renforce par un masque
    /// luminance (atténuation vers ombres / hautes lumières). Facteur négatif = adoucissement type glow.
    private static func applyClarity(_ input: CIImage, amount: Double) -> CIImage {
        guard abs(amount) > 1e-9 else { return input }
        let extent = input.extent
        let radius = clarityBlurRadiusPixels(for: extent)
        guard let blurred = gaussianBlurCI(input, radius: radius, extent: extent) else { return input }
        return DevelopPreviewKernels.applyClarityMidFrequency(
            orig: input,
            blurred: blurred,
            extent: extent,
            amountSigned100: amount
        )
    }

    /// **Hautes fréquences** (petit rayon ~3–7 px) : boost sur la luminance du détail uniquement,
    /// avec masque d’arête (Sobel sur luminance) pour atténuer sur les contours durs.
    private static func applyTexture(_ input: CIImage, amount: Double, referenceExtent: CGRect) -> CIImage {
        guard abs(amount) > 1e-9 else { return input }
        let extent = referenceExtent
        let radius = textureBlurRadiusPixels(for: extent)
        guard let lowSmall = gaussianBlurCI(input, radius: radius, extent: extent) else { return input }
        let edge: CIImage = textureGradientEdgeStrength01(from: input, extent: extent)
            ?? CIImage(color: CIColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1)).cropped(to: extent)
        return DevelopPreviewKernels.applyTextureHighFrequencyLuma(
            base: input,
            lowSmall: lowSmall,
            edgeStrength01: edge,
            extent: extent,
            amountSigned100: amount
        )
    }

    private static func clarityBlurRadiusPixels(for extent: CGRect) -> CGFloat {
        let diag = hypot(extent.width, extent.height)
        return max(22, min(58, diag * 0.0155))
    }

    private static func textureBlurRadiusPixels(for extent: CGRect) -> CGFloat {
        let diag = hypot(extent.width, extent.height)
        return max(2.6, min(8.2, 4.4 + diag * 0.00042))
    }

    /// Carte ~[0,1] de force de contour (gradient Sobel sur luminance linéaire Rec.709).
    private static func textureGradientEdgeStrength01(from input: CIImage, extent: CGRect) -> CIImage? {
        guard let yMono = linearRec709LuminanceAsRGB(input) else { return nil }
        let wH: [CGFloat] = [-1, 0, 1, -2, 0, 2, -1, 0, 1]
        let wV: [CGFloat] = [-1, -2, -1, 0, 0, 0, 1, 2, 1]
        guard let hGray = ciConvolution3x3(yMono, weights: wH, bias: 0.5, extent: extent),
              let vGray = ciConvolution3x3(yMono, weights: wV, bias: 0.5, extent: extent),
              let packR = isolateSobelToRed(hGray),
              let packG = isolateSobelToGreen(vGray),
              let packed = additionCompositing(foreground: packR, background: packG, extent: extent) else {
            return nil
        }
        let mag = DevelopPreviewKernels.applySobelMagnitudePacked(to: packed, extent: extent)
        guard let mono = CIFilter(name: "CIColorControls") else { return mag }
        mono.setValue(mag, forKey: kCIInputImageKey)
        mono.setValue(0.0, forKey: kCIInputSaturationKey)
        mono.setValue(1.45, forKey: kCIInputContrastKey)
        mono.setValue(0.02, forKey: kCIInputBrightnessKey)
        guard let boosted = mono.outputImage?.cropped(to: extent) else { return mag }
        guard let soften = CIFilter(name: "CIGaussianBlur") else { return boosted }
        soften.setValue(boosted, forKey: kCIInputImageKey)
        soften.setValue(1.1, forKey: kCIInputRadiusKey)
        return soften.outputImage?.cropped(to: extent)
    }

    private static func ciConvolution3x3(_ input: CIImage, weights: [CGFloat], bias: CGFloat, extent: CGRect) -> CIImage? {
        guard weights.count == 9,
              let f = CIFilter(name: "CIConvolution3X3") else { return nil }
        f.setValue(input, forKey: kCIInputImageKey)
        f.setValue(CIVector(values: weights, count: 9), forKey: "inputWeights")
        f.setValue(bias as NSNumber, forKey: "inputBias")
        return f.outputImage?.cropped(to: extent)
    }

    private static func isolateSobelToRed(_ gray: CIImage) -> CIImage? {
        guard let m = CIFilter(name: "CIColorMatrix") else { return nil }
        m.setValue(gray, forKey: kCIInputImageKey)
        m.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
        m.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
        m.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
        m.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        return m.outputImage
    }

    private static func isolateSobelToGreen(_ gray: CIImage) -> CIImage? {
        guard let m = CIFilter(name: "CIColorMatrix") else { return nil }
        m.setValue(gray, forKey: kCIInputImageKey)
        m.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
        m.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputGVector")
        m.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
        m.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        return m.outputImage
    }

    /// R = G = B = luminance linéaire Rec.709 — utilisé par le grain et la texture.
    private static func linearRec709LuminanceAsRGB(_ input: CIImage) -> CIImage? {
        guard let m = CIFilter(name: "CIColorMatrix") else { return nil }
        m.setValue(input, forKey: kCIInputImageKey)
        let y = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
        m.setValue(y, forKey: "inputRVector")
        m.setValue(y, forKey: "inputGVector")
        m.setValue(y, forKey: "inputBVector")
        m.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        return m.outputImage
    }

    private static func negateRGBChannels(_ input: CIImage) -> CIImage? {
        guard let m = CIFilter(name: "CIColorMatrix") else { return nil }
        m.setValue(input, forKey: kCIInputImageKey)
        m.setValue(CIVector(x: -1, y: 0, z: 0, w: 0), forKey: "inputRVector")
        m.setValue(CIVector(x: 0, y: -1, z: 0, w: 0), forKey: "inputGVector")
        m.setValue(CIVector(x: 0, y: 0, z: -1, w: 0), forKey: "inputBVector")
        return m.outputImage
    }

    private static func scaleRGBChannelsUniform(_ input: CIImage, scale: Double) -> CIImage? {
        guard let m = CIFilter(name: "CIColorMatrix") else { return nil }
        m.setValue(input, forKey: kCIInputImageKey)
        let s = scale
        m.setValue(CIVector(x: s, y: 0, z: 0, w: 0), forKey: "inputRVector")
        m.setValue(CIVector(x: 0, y: s, z: 0, w: 0), forKey: "inputGVector")
        m.setValue(CIVector(x: 0, y: 0, z: s, w: 0), forKey: "inputBVector")
        return m.outputImage
    }

    /// `foreground + background` (addition linéaire des composantes, adapté au pipeline flottant).
    private static func additionCompositing(foreground: CIImage, background: CIImage, extent: CGRect) -> CIImage? {
        guard let add = CIFilter(name: "CIAdditionCompositing") else { return nil }
        add.setValue(foreground, forKey: kCIInputImageKey)
        add.setValue(background, forKey: kCIInputBackgroundImageKey)
        return add.outputImage?.cropped(to: extent)
    }

    private static func gaussianBlurCI(_ input: CIImage, radius: CGFloat, extent: CGRect) -> CIImage? {
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else { return nil }
        blurFilter.setValue(input, forKey: kCIInputImageKey)
        blurFilter.setValue(radius, forKey: kCIInputRadiusKey)
        return blurFilter.outputImage?.cropped(to: extent)
    }

    /// combine curseur « Ombres » et « Point noir » (Lightroom : noirs vs tons très sombres).
    private static func combinedShadowAmount(sliderShadows: Double, blackPoint: Double) -> Double {
        let s = max(-100, min(100, sliderShadows))
        let bp = max(-100, min(100, blackPoint))
        var delta = 0.0
        if bp > 0 {
            delta -= bp * 0.74
        } else if bp < 0 {
            delta += (-bp) * 0.56
        }
        let combined = s + delta
        return max(-100, min(100, combined))
    }

    // MARK: - Grain (`CIRandomGenerator` → flou σ « taille », luminance Rec.709, cloche `CIToneCurve`, fusion `CIBlendWithMask`)
    //
    // `CIRandomGenerator` ne documente pas de réglage de graine : la texture est déterministe entre passes → grain « figé »,
    // proche d’une couche argentique fixe (pour un grain qui bouge frame à frame il faudrait une perturbation externe).

    private static func applyFilmGrain(
        _ input: CIImage,
        sizePct: Double,
        intensityPct: Double,
        roughnessPct: Double,
        referenceExtent: CGRect
    ) -> CIImage {
        guard intensityPct > 0 else { return input }
        return applyGrainNoiseOverlay(
            input,
            sizePct: sizePct,
            intensityPct: intensityPct,
            roughnessPct: roughnessPct,
            referenceExtent: referenceExtent
        )
    }

    /// Grain achromatique : bruit corrélé par Gaussien (curseur Taille), luminance Rec.709, masque tons moyens en cloche.
    private static func applyGrainNoiseOverlay(
        _ input: CIImage,
        sizePct: Double,
        intensityPct: Double,
        roughnessPct: Double,
        referenceExtent: CGRect
    ) -> CIImage {
        let intensity = min(1, max(0, intensityPct / 100))
        guard intensity > 0.001 else { return input }
        let s = min(1, max(0, sizePct / 100))
        let rough = min(100, max(0, roughnessPct)) / 100

        guard let noiseFilter = CIFilter(name: "CIRandomGenerator"),
              let noiseRaw = noiseFilter.outputImage?.cropped(to: referenceExtent) else { return input }

        let noiseBase: CIImage = {
            guard let cc = CIFilter(name: "CIColorControls") else { return noiseRaw }
            cc.setValue(noiseRaw, forKey: kCIInputImageKey)
            cc.setValue(0.0, forKey: kCIInputSaturationKey)
            cc.setValue(1.65, forKey: kCIInputContrastKey)
            cc.setValue(-0.02, forKey: kCIInputBrightnessKey)
            return cc.outputImage ?? noiseRaw
        }()

        var noiseRoughBranch = noiseBase
        if rough > 0.004,
           let ccRough = CIFilter(name: "CIColorControls") {
            ccRough.setValue(noiseBase, forKey: kCIInputImageKey)
            ccRough.setValue(0.0, forKey: kCIInputSaturationKey)
            ccRough.setValue(1.0 + rough * 0.62, forKey: kCIInputContrastKey)
            ccRough.setValue(-0.018 * rough, forKey: kCIInputBrightnessKey)
            noiseRoughBranch = ccRough.outputImage ?? noiseBase
        }

        let grainSigma = CGFloat(0.42 + s * 6.35)
        let grainSigmaFine = CGFloat(max(0.22, Double(grainSigma) * 0.52))

        guard let blurredMain = gaussianBlurCI(noiseBase, radius: grainSigma, extent: referenceExtent) else { return input }
        guard let blurredFine = gaussianBlurCI(noiseRoughBranch, radius: grainSigmaFine, extent: referenceExtent) else { return input }

        guard let grainSmooth = grainHighPassSubtractDC(blurredMain, blurRadius: grainSigma, extent: referenceExtent) else { return input }
        guard let grainRoughHF = grainHighPassSubtractDC(blurredFine, blurRadius: grainSigmaFine, extent: referenceExtent) else { return input }

        let grainTexture: CIImage = {
            guard rough > 0.004,
                  let mixTex = CIFilter(name: "CIMix") else { return grainSmooth }
            mixTex.setValue(grainRoughHF, forKey: kCIInputImageKey)
            mixTex.setValue(grainSmooth, forKey: kCIInputBackgroundImageKey)
            mixTex.setValue(rough, forKey: kCIInputAmountKey)
            return mixTex.outputImage?.cropped(to: referenceExtent) ?? grainSmooth
        }()

        guard let lumaGrain = linearRec709LuminanceAsRGB(grainTexture) else { return input }

        let amp = intensity * 0.52
        guard let scaledGrain = scaleRGBChannelsUniform(lumaGrain, scale: amp) else { return input }

        guard let grainMix = additionCompositing(foreground: scaledGrain, background: input, extent: referenceExtent) else { return input }

        guard let bell = grainBellCurveMask(from: input, extent: referenceExtent),
              let merge = CIFilter(name: "CIBlendWithMask") else {
            return grainMix
        }
        merge.setValue(grainMix, forKey: kCIInputImageKey)
        merge.setValue(input, forKey: kCIInputBackgroundImageKey)
        merge.setValue(bell, forKey: kCIInputMaskImageKey)
        return merge.outputImage?.cropped(to: referenceExtent) ?? grainMix
    }

    private static func grainBellCurveMask(from input: CIImage, extent: CGRect) -> CIImage? {
        guard let lumaMask = linearRec709LuminanceAsRGB(input) else { return nil }
        guard let curve = CIFilter(name: "CIToneCurve") else {
            return DevelopPreviewKernels.applyGrainMidtoneVisibility(to: lumaMask, extent: extent)
        }
        curve.setValue(lumaMask, forKey: kCIInputImageKey)
        curve.setValue(CIVector(x: 0, y: 0), forKey: "inputPoint0")
        curve.setValue(CIVector(x: 0.25, y: 0.6), forKey: "inputPoint1")
        curve.setValue(CIVector(x: 0.5, y: 1.0), forKey: "inputPoint2")
        curve.setValue(CIVector(x: 0.75, y: 0.6), forKey: "inputPoint3")
        curve.setValue(CIVector(x: 1, y: 0), forKey: "inputPoint4")
        return curve.outputImage?.cropped(to: extent)
            ?? DevelopPreviewKernels.applyGrainMidtoneVisibility(to: lumaMask, extent: extent)
    }

    private static func grainHighPassSubtractDC(_ correlated: CIImage, blurRadius: CGFloat, extent: CGRect) -> CIImage? {
        let dcRadius = CGFloat(max(6.0, Double(blurRadius) * 5.5))
        guard let grainLow = gaussianBlurCI(correlated, radius: dcRadius, extent: extent) else { return nil }
        guard let negLow = negateRGBChannels(grainLow) else { return nil }
        return additionCompositing(foreground: correlated, background: negLow, extent: extent)
    }

    // MARK: - Vignetage combiné

    private static func applyCombinedVignette(_ input: CIImage, settings: DevelopSettings) -> CIImage {
        var intensity: Double = 0
        if settings.enableVignetting {
            intensity += settings.vignetteExposureAmount / 100 * 0.82
        }
        if settings.enableMasks {
            intensity += abs(settings.maskRadialBlend) / 100 * 0.92
        }
        intensity += settings.vignetteBlackPointAmount / 550
        intensity = min(1, max(0, intensity))

        guard intensity > 0.004,
              let f = CIFilter(name: "CIVignette") else { return input }
        f.setValue(input, forKey: kCIInputImageKey)
        let extent = input.extent
        let softness = max(0.15, settings.vignetteSoftnessAmount / 100)
        let baseRadius = Double(min(extent.width, extent.height)) * 0.5
        f.setValue(baseRadius * (0.5 + softness * 0.5), forKey: kCIInputRadiusKey)
        f.setValue(intensity * 0.97, forKey: kCIInputIntensityKey)
        return f.outputImage ?? input
    }

    private static func applyExposure(_ input: CIImage, ev: Double) -> CIImage {
        DevelopPreviewKernels.applySceneExposureWithShoulder(to: input, extent: input.extent, ev: ev)
    }

    private static func applyContrast(_ input: CIImage, amount: Double) -> CIImage {
        let midpoint = estimatedLinearLuminanceMidpoint(for: input)
        return DevelopPreviewKernels.applyLinearLuminanceContrast(
            to: input,
            extent: input.extent,
            amount: amount,
            midpoint: midpoint
        )
    }

    /// Approximation rapide du pivot tonal : moyenne linéaire 1×1, bornée autour des valeurs photographiques utiles.
    /// La vraie médiane est trop chère pour l'aperçu interactif ; ce pivot donne une S-curve dépendante de l'image.
    private static func estimatedLinearLuminanceMidpoint(for input: CIImage) -> Double {
        guard let average = CIFilter(name: "CIAreaAverage"),
              let colorSpace = CGColorSpace(name: CGColorSpace.linearSRGB) else {
            return 0.18
        }
        average.setValue(input, forKey: kCIInputImageKey)
        average.setValue(CIVector(cgRect: input.extent), forKey: kCIInputExtentKey)
        guard let out = average.outputImage else { return 0.18 }

        var rgba = [Float](repeating: 0, count: 4)
        rgba.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            context.render(
                out,
                toBitmap: base,
                rowBytes: MemoryLayout<Float>.size * 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBAf,
                colorSpace: colorSpace
            )
        }
        let y = 0.2126 * Double(rgba[0]) + 0.7152 * Double(rgba[1]) + 0.0722 * Double(rgba[2])
        guard y.isFinite else { return 0.18 }
        return min(0.72, max(0.08, y))
    }

    private static func applyBrightness(_ input: CIImage, brightness: Double) -> CIImage {
        guard brightness != 0,
              let f = CIFilter(name: "CIColorControls") else { return input }
        f.setValue(input, forKey: kCIInputImageKey)
        f.setValue(brightness / 100.0, forKey: kCIInputBrightnessKey)
        f.setValue(1.0, forKey: kCIInputContrastKey)
        f.setValue(1.0, forKey: kCIInputSaturationKey)
        return f.outputImage ?? input
    }

    private static func applyHue(_ input: CIImage, hueDegrees: Double) -> CIImage {
        guard hueDegrees != 0,
              let f = CIFilter(name: "CIHueAdjust") else { return input }
        f.setValue(input, forKey: kCIInputImageKey)
        let radians = (hueDegrees / 100.0) * .pi
        f.setValue(radians, forKey: kCIInputAngleKey)
        return f.outputImage ?? input
    }

    private static func applyColorControls(
        _ input: CIImage,
        saturationDelta: Double,
        contrastDelta: Double,
        brightnessDelta: Double
    ) -> CIImage {
        guard saturationDelta != 0 || contrastDelta != 0 || brightnessDelta != 0,
              let f = CIFilter(name: "CIColorControls") else { return input }
        f.setValue(input, forKey: kCIInputImageKey)
        f.setValue(1.0 + saturationDelta / 100.0, forKey: kCIInputSaturationKey)
        f.setValue(1.0 + contrastDelta / 280.0, forKey: kCIInputContrastKey)
        f.setValue(brightnessDelta / 100.0, forKey: kCIInputBrightnessKey)
        return f.outputImage ?? input
    }

    private static func applyVibrance(_ input: CIImage, amount: Double) -> CIImage {
        guard let f = CIFilter(name: "CIVibrance") else { return input }
        f.setValue(input, forKey: kCIInputImageKey)
        f.setValue(amount / 50.0, forKey: "inputAmount")
        return f.outputImage ?? input
    }

    private static func applyHighlightShadow(_ input: CIImage, highlights: Double, shadows: Double) -> CIImage {
        guard let f = CIFilter(name: "CIHighlightShadowAdjust") else { return input }
        f.setValue(input, forKey: kCIInputImageKey)
        // CIHighlightShadowAdjust :
        //   - inputHighlightAmount ∈ [0, 1], 1 = inchangé, 0 = récupération max (assombrit les hautes lumières).
        //   - inputShadowAmount ∈ [-1, 1], 0 = inchangé, +1 = relève les ombres, -1 = les assombrit.
        let hlNeg = max(0, -highlights) / 100.0
        let highlightAmount = max(0.0, min(1.0, 1.0 - hlNeg))

        let shadowAmount = max(-1.0, min(1.0, shadows / 100.0))
        f.setValue(highlightAmount, forKey: "inputHighlightAmount")
        f.setValue(shadowAmount, forKey: "inputShadowAmount")
        return f.outputImage ?? input
    }

    private static func applyTemperatureTint(_ input: CIImage, temperature: Double, tint: Double) -> CIImage {
        guard let f = CIFilter(name: "CITemperatureAndTint") else { return input }
        f.setValue(input, forKey: kCIInputImageKey)
        // CITemperatureAndTint adapte la chromaticité : target plus bas (Kelvin) = image plus chaude.
        // Le slider va vers le jaune dans le sens positif, on baisse donc le Kelvin cible quand temperature > 0.
        let neutral = CIVector(x: 6500, y: 0)
        let target = CIVector(x: 6500 - temperature * 30, y: -tint)
        f.setValue(neutral, forKey: "inputNeutral")
        f.setValue(target, forKey: "inputTargetNeutral")
        return f.outputImage ?? input
    }

    private static func applyLensDistortion(_ input: CIImage, amount: Double) -> CIImage {
        guard amount != 0,
              let f = CIFilter(name: "CIPinchDistortion") else { return input }
        let extent = input.extent
        let center = CIVector(x: extent.midX, y: extent.midY)
        let radius = Double(min(extent.width, extent.height)) * 0.48
        f.setValue(input, forKey: kCIInputImageKey)
        f.setValue(center, forKey: kCIInputCenterKey)
        f.setValue(radius, forKey: kCIInputRadiusKey)
        f.setValue(amount / 800.0, forKey: kCIInputScaleKey)
        return f.outputImage ?? input
    }

    private static func applyChromaticAberration(_ input: CIImage, amount: Double) -> CIImage {
        guard amount != 0 else { return input }
        let extent = input.extent
        let shift = CGFloat(amount / 100.0 * 5.0)
        let transform = CGAffineTransform(translationX: shift, y: -shift * 0.35)
        let shifted = input.transformed(by: transform).cropped(to: extent)

        guard let mix = CIFilter(name: "CIMix") else { return input }
        mix.setValue(shifted, forKey: kCIInputImageKey)
        mix.setValue(input, forKey: kCIInputBackgroundImageKey)
        mix.setValue(min(0.55, abs(amount) / 160.0), forKey: kCIInputAmountKey)
        return mix.outputImage ?? input
    }

    /// Variante de `applyColorCurves` avec courbes distinctes par canal.
    private static func applyChannelColorCurves(_ input: CIImage, r: [Double], g: [Double], b: [Double]) -> CIImage {
        precondition(r.count == g.count && g.count == b.count, "Channel curves must share point count")
        var floats: [Float] = []
        floats.reserveCapacity(r.count * 3)
        for i in 0..<r.count {
            floats.append(Float(r[i]))
            floats.append(Float(g[i]))
            floats.append(Float(b[i]))
        }
        let curveData: Data = floats.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return Data() }
            return Data(bytes: base, count: ptr.count * MemoryLayout<Float>.size)
        }
        guard !curveData.isEmpty,
              let space = CGColorSpace(name: CGColorSpace.linearSRGB),
              let out = applyColorCurvesCore(input: input, curvesData: curveData, colorSpace: space) else {
            return input
        }
        return out
    }

    // MARK: - TSL par couleur (style Lightroom HSL)

    /// Applique des ajustements Teinte/Saturation/Luminance par bande de couleur (8 teintes).
    /// Chaque teinte cible un segment de 45° du cercle chromatique ; les zones de transition sont douces.
    private static func applyTSLPerColor(_ input: CIImage, palette: SelectiveColorPalette) -> CIImage {
        let hasAnyAdjustment = palette.channels.contains { ch in
            ch.hue != 0 || ch.saturation != 0 || ch.luminance != 0
        }
        guard hasAnyAdjustment else { return input }

        var output = input
        let hueAngles: [Double] = [0, 30, 60, 120, 180, 240, 270, 300]

        for (i, channel) in palette.channels.enumerated() {
            guard channel.hue != 0 || channel.saturation != 0 || channel.luminance != 0 else { continue }
            output = applyTSLBand(
                output,
                targetHueDeg: hueAngles[i],
                hueShift: channel.hue,
                satShift: channel.saturation,
                lumShift: channel.luminance
            )
        }
        return output
    }

    /// Ajuste une bande de teinte spécifique via CIColorCube (approximation par mélange masqué).
    private static func applyTSLBand(
        _ input: CIImage,
        targetHueDeg: Double,
        hueShift: Double,
        satShift: Double,
        lumShift: Double
    ) -> CIImage {
        DevelopPreviewKernels.applyTSLBandAdjust(
            to: input,
            extent: input.extent,
            targetHueDeg: targetHueDeg,
            hueShift: hueShift,
            satShift: satShift,
            lumShift: lumShift
        )
    }

    // MARK: - Tone mapping sigmoïde (inspiration darktable iop/sigmoid.c)
    //
    // Algorithme :
    //   1. Décale l'entrée par `pivotEV` (point d'ancrage des tons moyens)
    //   2. Applique une sigmoïde généralisée :
    //        f(x) = white · x^c / (x^c + (pivot/white)^c · (white − x)^c)   (forme rationnelle stable)
    //      avec `c` = contrast (pente). `c=1` est neutre, `c>1` accentue le contraste.
    //   3. Appliqué identiquement aux 3 canaux RGB → préserve la teinte (pas de drift).
    //
    // Implémentation Core Image : on précalcule une LUT 1D de 33 points à partir de la formule analytique,
    // puis on l'applique via CIColorCurves (très rapide, GPU-friendly).
    private static func applySigmoidToneMapping(
        _ input: CIImage,
        contrast: Double,
        pivotEV: Double,
        whitePoint: Double
    ) -> CIImage {
        let c = max(0.4, min(2.5, contrast))
        let wp = max(0.5, min(1.2, whitePoint))
        let pivotShift = pow(2.0, max(-3.0, min(3.0, pivotEV))) // EV → multiplicateur linéaire

        let n = 33
        var samples: [Double] = []
        samples.reserveCapacity(n)
        for i in 0..<n {
            let x = Double(i) / Double(n - 1) // ∈ [0, 1]
            // Échantillonne en domaine étendu pour donner du headroom (jusqu'à 1.5× display white).
            let xScene = x * 1.5 * pivotShift
            let xClamped = max(0.001, xScene)
            // Sigmoid de Naka-Rushton modifiée : y = wp · x^c / (x^c + 0.5^c · (wp − x)^c)
            // Approximation pratique : y = wp · x^c / (x^c + a)  avec a = (wp/2)^c · (1 − pow(min(1, x/wp), 1))
            let normalized = min(0.999 * wp, xClamped)
            let xPow = pow(normalized, c)
            let halfPow = pow(0.5, c)
            let y = wp * xPow / (xPow + halfPow * pow(max(0.001, wp - normalized), c))
            samples.append(min(1.0, max(0.0, y)))
        }
        return applyColorCurves(input, samples: samples)
    }

    // MARK: - Réduction de bruit

    private static func applyNoiseReduction(
        _ input: CIImage,
        luminance: Double,
        chrominance: Double
    ) -> CIImage {
        guard luminance > 0 || chrominance > 0 else { return input }
        var output = input

        if luminance > 0 {
            guard let nr = CIFilter(name: "CINoiseReduction") else { return output }
            nr.setValue(output, forKey: kCIInputImageKey)
            nr.setValue(luminance / 100.0 * 0.06, forKey: "inputNoiseLevel")
            nr.setValue(luminance / 100.0 * 3.0, forKey: "inputSharpness")
            output = nr.outputImage ?? output
        }

        if chrominance > 0 {
            let radius = max(0.5, chrominance / 100.0 * 4.0)
            guard let blur = CIFilter(name: "CIGaussianBlur") else { return output }
            let extent = output.extent

            blur.setValue(output, forKey: kCIInputImageKey)
            blur.setValue(radius, forKey: kCIInputRadiusKey)
            guard let blurred = blur.outputImage?.cropped(to: extent) else { return output }

            guard let cc = CIFilter(name: "CIColorControls") else { return output }
            cc.setValue(blurred, forKey: kCIInputImageKey)
            cc.setValue(1.0, forKey: kCIInputSaturationKey)
            cc.setValue(1.0, forKey: kCIInputContrastKey)
            cc.setValue(0.0, forKey: kCIInputBrightnessKey)
            guard let chromaSmoothed = cc.outputImage else { return output }

            guard let mix = CIFilter(name: "CIMix") else { return output }
            mix.setValue(chromaSmoothed, forKey: kCIInputImageKey)
            mix.setValue(output, forKey: kCIInputBackgroundImageKey)
            mix.setValue(min(0.85, chrominance / 100.0 * 0.65), forKey: kCIInputAmountKey)
            output = mix.outputImage ?? output
        }

        return output
    }

}

// MARK: - Chargement fichier (RAW + bitmap)
//
// **Espace colorimétrique** : les RAW sont décodés par `CIRAWFilter` en linéaire scène ; ils ne passent pas par
// `ColorProfileReader.describeIfBitmap`. La normalisation ICC des bitmaps est faite dans `ZenithSourceColorNormalizer`.

/// Déclaré dans ce fichier pour garantir qu’il est toujours dans le même target que `DevelopPreviewRenderer`
/// (évite « Cannot find 'ZenithImageSourceLoader' in scope » si le `.swift` isolé n’est pas compilé).
nonisolated enum ZenithImageSourceLoader {

    /// Verrou **uniquement** pour le chemin `CIRAWFilter` : les JPEG/TIFF/HEIC passent en parallèle sans
    /// bloquer l’aperçu, l’histogramme ou la pellicule (sinon tout le monde attendait sur un seul verrou).
    private static let rawDecodeLock = NSLock()

    /// Heuristique ImageIO : évite d’appeler `CIRAWFilter` sur chaque fichier (coûteux) et permet de
    /// ne sérialiser que les vrais flux RAW.
    private static func isLikelyCameraRAW(at url: URL) -> Bool {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let typeId = CGImageSourceGetType(src) as String?
        else {
            return false
        }
        guard let ut = UTType(typeId) else { return false }
        return ut.conforms(to: .rawImage)
    }

    /// - Parameters:
    ///   - maxPixelDimension: borne le côté le plus long à l’étape de décodage RAW (`scaleFactor`) ou par redimensionnement.
    ///   - draftMode: décodage RAW plus rapide (aperçu proxy / miniatures) avec légère perte de qualité.
    static func ciImage(
        contentsOf url: URL,
        maxPixelDimension: CGFloat?,
        draftMode: Bool = false
    ) -> CIImage? {
        if isLikelyCameraRAW(at: url) {
            rawDecodeLock.lock()
            defer { rawDecodeLock.unlock() }
            if let raw = CIRAWFilter(imageURL: url) {
                configureProfessionalRAW(filter: raw, maxPixelDimension: maxPixelDimension, draftMode: draftMode)
                if let out = raw.outputImage {
                    return out
                }
            }
        }
        return decodeBitmap(contentsOf: url, maxPixelDimension: maxPixelDimension)
    }

    private static func configureProfessionalRAW(
        filter raw: CIRAWFilter,
        maxPixelDimension: CGFloat?,
        draftMode: Bool
    ) {
        raw.isDraftModeEnabled = draftMode
        if let latest = raw.supportedDecoderVersions.last {
            raw.decoderVersion = latest
        }

        raw.exposure = 0

        raw.boostAmount = 0
        raw.boostShadowAmount = 1

        if raw.isLocalToneMapSupported {
            raw.localToneMapAmount = 0
        }
        if raw.isContrastSupported {
            raw.contrastAmount = 0
        }
        if raw.isDetailSupported {
            raw.detailAmount = 0
        }
        if raw.isSharpnessSupported {
            raw.sharpnessAmount = 0
        }
        if raw.isLuminanceNoiseReductionSupported {
            raw.luminanceNoiseReductionAmount = 0
        }
        if raw.isColorNoiseReductionSupported {
            raw.colorNoiseReductionAmount = 0
        }
        if raw.isMoireReductionSupported {
            raw.moireReductionAmount = 0
        }

        raw.extendedDynamicRangeAmount = draftMode ? 1 : 2
        raw.isGamutMappingEnabled = false

        if raw.isLensCorrectionSupported {
            raw.isLensCorrectionEnabled = true
        }

        if raw.isHighlightRecoverySupported {
            raw.isHighlightRecoveryEnabled = true
        }

        let native = raw.nativeSize
        let maxSide = max(native.width, native.height)
        if let cap = maxPixelDimension, maxSide > 0, cap > 0, maxSide > cap {
            raw.scaleFactor = Float(min(1, cap / maxSide))
        } else {
            raw.scaleFactor = 1
        }
    }

    private static func decodeBitmap(contentsOf url: URL, maxPixelDimension: CGFloat?) -> CIImage? {
        var options: [CIImageOption: Any] = [.applyOrientationProperty: true]
        options[.expandToHDR] = true

        guard var output = CIImage(contentsOf: url, options: options) else { return nil }
        let dim = max(output.extent.width, output.extent.height)
        if let cap = maxPixelDimension, dim > cap, cap > 0 {
            let s = cap / dim
            output = output.transformed(by: CGAffineTransform(scaleX: s, y: s))
        }
        return output
    }
}
