//
//  DevelopPreviewRenderer.swift
//  Zenith
//

import AppKit
import CoreImage

enum DevelopPreviewRenderer {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])
    private static let previewMaxDimension: CGFloat = 4096

    /// CIImage après pipeline développement (même logique que l’aperçu).
    static func developedCIImage(url: URL, settings: DevelopSettings) -> CIImage? {
        guard let ci = CIImage(contentsOf: url) else { return nil }
        var output = ci
        let maxDim = max(output.extent.width, output.extent.height)
        if maxDim > previewMaxDimension {
            let s = previewMaxDimension / maxDim
            output = output.transformed(by: CGAffineTransform(scaleX: s, y: s))
        }
        let workExtent = output.extent

        // 1 — Noir & blanc
        if settings.enableBlackWhite {
            output = applyBlackWhiteMix(output, settings: settings)
        }

        // 2 — Exposition / luminosité / contraste (carte Basique)
        if settings.enableBasicAdjustments {
            if settings.exposureEV != 0 {
                output = applyExposure(output, ev: settings.exposureEV)
            }
            output = applyBrightness(output, brightness: settings.brightness)
            output = applyColorControls(
                output,
                saturationDelta: 0,
                contrastDelta: settings.contrast,
                brightnessDelta: 0
            )
            let shadowBoost = settings.shadows + settings.blackPoint * 0.35
            let hl = settings.highlights
            if hl != 0 || shadowBoost != 0 {
                output = applyHighlightShadow(output, highlights: hl, shadows: shadowBoost)
            }
        }

        // 3 — Teinte / saturation / vibrance (carte Teinte et saturation)
        if settings.enableHueSaturation {
            if settings.tslHue != 0 {
                output = applyHue(output, hueDegrees: settings.tslHue)
            }
            output = applyColorControls(
                output,
                saturationDelta: settings.tslSaturation + settings.saturation,
                contrastDelta: 0,
                brightnessDelta: settings.tslLuminance
            )
            if settings.vibrance != 0 {
                output = applyVibrance(output, amount: settings.vibrance)
            }
        }

        // 4 — Balance des blancs
        if settings.enableWhiteBalance, settings.temperature != 0 || settings.tint != 0 {
            output = applyTemperatureTint(output, temperature: settings.temperature, tint: settings.tint)
        }

        // 5 — Niveaux (approximation tonalité entrée/sortie)
        if settings.enableLevels {
            output = applyLevelsApproximation(output, settings: settings)
        }

        // 6 — Courbes (gamma maître)
        if settings.enableCurves, settings.curvesMasterIntensity != 0 {
            output = applyGammaCurve(output, intensity: settings.curvesMasterIntensity)
        }

        // 7 — Balance des couleurs (approximation légère)
        if settings.enableColorBalance {
            output = applyColorBalanceApprox(output, settings: settings)
        }

        // 8 — Clarté / texture (Basique)
        if settings.enableBasicAdjustments {
            var clarityAmount = settings.clarity
            if settings.enableSelectiveClarity {
                let toneWeights: [Double] = [0.85, 1.0, 1.1]
                let idx = min(max(settings.selectiveClarityTone, 0), 2)
                clarityAmount *= toneWeights[idx]
            }
            if clarityAmount != 0 {
                output = applyClarity(output, amount: clarityAmount)
            }
            if settings.texture != 0 {
                output = applyTexture(output, amount: settings.texture, referenceExtent: workExtent)
            }
        }

        // 9 — Netteté (carte dédiée)
        if settings.enableSharpness, settings.sharpnessAmountPct > 0 {
            output = applySharpnessDetail(
                output,
                radiusPx: settings.sharpnessRadiusPx,
                amountPct: settings.sharpnessAmountPct
            )
        }

        // 10 — Grain (carte dédiée)
        if settings.enableGrain, settings.grainIntensityPct > 0 {
            output = applyFilmGrain(
                output,
                sizePct: settings.grainSizePct,
                intensityPct: settings.grainIntensityPct,
                referenceExtent: workExtent
            )
        }

        // 11 — Objectif
        if settings.enableLensCorrection {
            if settings.lensCorrection != 0 {
                output = applyLensDistortion(output, amount: settings.lensCorrection)
            }
            if settings.chromaticAberration != 0 {
                output = applyChromaticAberration(output, amount: settings.chromaticAberration)
            }
        }

        // 12 — Vignetage + masque radial
        if settings.enableVignetting || settings.enableMasks {
            output = applyCombinedVignette(output, settings: settings)
        }

        output = output.cropped(to: workExtent)
        return output
    }

    static func render(url: URL, settings: DevelopSettings) -> NSImage? {
        guard let output = developedCIImage(url: url, settings: settings) else {
            return NSImage(contentsOf: url)
        }
        let extent = output.extent
        guard let cg = context.createCGImage(output, from: extent) else {
            return NSImage(contentsOf: url)
        }
        return NSImage(cgImage: cg, size: NSSize(width: extent.width, height: extent.height))
    }

    // MARK: - Noir & blanc

    private static func applyBlackWhiteMix(_ input: CIImage, settings: DevelopSettings) -> CIImage {
        let mix = min(1, max(0, settings.bwIntensity / 100))
        guard mix > 0.01 else { return input }

        guard let mono = CIFilter(name: "CIColorMonochrome") else { return input }
        mono.setValue(input, forKey: kCIInputImageKey)
        mono.setValue(CIColor.gray, forKey: kCIInputColorKey)
        let toneShift = 1 + settings.bwTone / 400
        mono.setValue(mix * 0.9 * toneShift, forKey: kCIInputIntensityKey)
        guard let gray = mono.outputImage else { return input }

        guard let blend = CIFilter(name: "CIMix") else { return gray }
        blend.setValue(gray, forKey: kCIInputImageKey)
        blend.setValue(input, forKey: kCIInputBackgroundImageKey)
        blend.setValue(mix, forKey: kCIInputAmountKey)
        return blend.outputImage ?? input
    }

    // MARK: - Niveaux

    private static func applyLevelsApproximation(_ input: CIImage, settings: DevelopSettings) -> CIImage {
        var out = input
        let bl = settings.levelsInputBlack / 100
        let wh = max(0.01, settings.levelsInputWhite / 100)
        let mid = settings.levelsMidtone / 100
        let range = wh - bl
        guard range > 0.01 else { return out }

        let ev = log2(max(0.2, range * 1.1))
        if ev != 0 {
            out = applyExposure(out, ev: ev * 0.35)
        }
        if mid > 0.01, mid < 0.99 {
            let power = 0.5 + mid
            out = applyGammaValue(out, power: power)
        }
        return out
    }

    private static func applyGammaValue(_ input: CIImage, power: Double) -> CIImage {
        guard let f = CIFilter(name: "CIGammaAdjust") else { return input }
        f.setValue(input, forKey: kCIInputImageKey)
        f.setValue(power, forKey: "inputPower")
        return f.outputImage ?? input
    }

    private static func applyGammaCurve(_ input: CIImage, intensity: Double) -> CIImage {
        let t = intensity / 100
        let power = 1 - t * 0.45
        return applyGammaValue(input, power: max(0.4, min(1.6, power)))
    }

    // MARK: - Balance des couleurs (approximation)

    private static func applyColorBalanceApprox(_ input: CIImage, settings: DevelopSettings) -> CIImage {
        let h = (settings.cbHighlightHue + settings.cbMidtoneHue + settings.cbShadowHue) / 3
        let s = (settings.cbHighlightSaturation + settings.cbMidtoneSaturation + settings.cbShadowSaturation) / 3
        guard h != 0 || s != 0 else { return input }
        var out = input
        if h != 0 {
            out = applyHue(out, hueDegrees: h * 0.6)
        }
        if s != 0 {
            out = applyColorControls(out, saturationDelta: s * 0.35, contrastDelta: 0, brightnessDelta: 0)
        }
        return out
    }

    // MARK: - Netteté

    private static func applySharpnessDetail(_ input: CIImage, radiusPx: Double, amountPct: Double) -> CIImage {
        guard let f = CIFilter(name: "CISharpenLuminance") else { return input }
        f.setValue(input, forKey: kCIInputImageKey)
        let amt = (amountPct / 100) * (0.2 + min(radiusPx, 12) / 25)
        f.setValue(min(2.5, amt), forKey: kCIInputSharpnessKey)
        return f.outputImage ?? input
    }

    // MARK: - Grain

    private static func applyFilmGrain(
        _ input: CIImage,
        sizePct: Double,
        intensityPct: Double,
        referenceExtent: CGRect
    ) -> CIImage {
        guard intensityPct > 0 else { return input }
        let scale = 0.35 + (sizePct / 100) * 1.2
        let amountScaled = intensityPct * scale * 0.65
        return applyTexture(input, amount: amountScaled, referenceExtent: referenceExtent)
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
        guard let evFilter = CIFilter(name: "CIExposureAdjust") else { return input }
        evFilter.setValue(input, forKey: kCIInputImageKey)
        evFilter.setValue(ev, forKey: kCIInputEVKey)
        return evFilter.outputImage ?? input
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
        guard let f = CIFilter(name: "CIHueAdjust") else { return input }
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
        f.setValue(1.0 + contrastDelta / 200.0, forKey: kCIInputContrastKey)
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
        f.setValue(1.0 + highlights / 100.0, forKey: "inputHighlightAmount")
        f.setValue(1.0 + shadows / 100.0, forKey: "inputShadowAmount")
        return f.outputImage ?? input
    }

    private static func applyTemperatureTint(_ input: CIImage, temperature: Double, tint: Double) -> CIImage {
        guard let f = CIFilter(name: "CITemperatureAndTint") else { return input }
        f.setValue(input, forKey: kCIInputImageKey)
        let neutral = CIVector(x: 6500, y: 0)
        let target = CIVector(x: 6500 + temperature * 30, y: tint)
        f.setValue(neutral, forKey: "inputNeutral")
        f.setValue(target, forKey: "inputTargetNeutral")
        return f.outputImage ?? input
    }

    private static func applyClarity(_ input: CIImage, amount: Double) -> CIImage {
        guard let f = CIFilter(name: "CISharpenLuminance") else { return input }
        f.setValue(input, forKey: kCIInputImageKey)
        f.setValue(min(2.0, 0.15 + abs(amount) / 80.0), forKey: kCIInputSharpnessKey)
        return f.outputImage ?? input
    }

    private static func applyTexture(_ input: CIImage, amount: Double, referenceExtent: CGRect) -> CIImage {
        guard amount != 0 else { return input }
        let intensity = min(1.0, abs(amount) / 100.0)

        guard let noiseFilter = CIFilter(name: "CIRandomGenerator"),
              let noise = noiseFilter.outputImage?.cropped(to: referenceExtent) else { return input }

        guard let mono = CIFilter(name: "CIColorControls") else { return input }
        mono.setValue(noise, forKey: kCIInputImageKey)
        mono.setValue(0.0, forKey: kCIInputSaturationKey)
        mono.setValue(1.5, forKey: kCIInputContrastKey)
        guard let grain = mono.outputImage else { return input }

        guard let soft = CIFilter(name: "CISoftLightBlendMode") else { return input }
        soft.setValue(input, forKey: kCIInputBackgroundImageKey)
        soft.setValue(grain, forKey: kCIInputImageKey)
        guard let textured = soft.outputImage else { return input }

        guard let mix = CIFilter(name: "CIMix") else { return input }
        mix.setValue(textured, forKey: kCIInputImageKey)
        mix.setValue(input, forKey: kCIInputBackgroundImageKey)
        mix.setValue(intensity * 0.45, forKey: kCIInputAmountKey)
        return mix.outputImage ?? input
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

}
