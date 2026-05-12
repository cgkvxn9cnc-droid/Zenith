//
//  DevelopProSharpening.swift
//  Zenith
//
//  Netteté « pro » : trois passes USM sur la **luminance linéaire Rec.709** puis recombination RVB (facteur Y_out/Y),
//  pour éviter la dérive d’exposition de l’USM RVB additif. Masque Sobel pour les aplats, atténuation des hautes lumières.
//

import CoreImage
import Foundation

nonisolated enum DevelopProSharpening {

    /// Applique la netteté à trois échelles sur une image déjà dans l’espace de travail linéaire du contexte.
    static func apply(_ input: CIImage, settings: DevelopSettings, quality: DevelopPipelineQuality) -> CIImage {
        let masterPct = DevelopPipelineColorMath.softenUnsigned(settings.sharpnessAmountPct, maxValue: 100, exponent: 1.12)
        let master = min(100, max(0, masterPct)) / 100
        guard master > 0.001 else { return input }

        let extent = input.extent
        let qScale: CGFloat = quality == .fast ? 0.82 : 1.0

        let edgeR = CGFloat(settings.sharpnessRadiusPx) * qScale
        let radiusEdge = max(0.9, min(22, edgeR))
        let radiusDetail = max(0.32, min(2.9, radiusEdge * 0.38))
        let radiusStructure = max(6.5, min(46, radiusEdge * 11.2))

        let u = min(100, max(0, settings.sharpnessDetailPct)) / 100
        // Plus « Détail » est haut, plus le seuil est strict (moins de renforcement du très fin grain).
        let tDetail = 0.0012 + (1 - u) * 0.026
        let tEdge = 0.0018 + (1 - u) * 0.032
        let tStruct = 0.0032 + (1 - u) * 0.036

        let wDetail = 0.26 + u * 0.48
        let wEdge = 0.42 + (1 - u) * 0.28
        let wStruct = max(0.1, 1.05 - wDetail - wEdge)
        let sumW = wDetail + wEdge + wStruct

        let amtDetail = master * (wDetail / sumW) * 1.12
        let amtEdge = master * (wEdge / sumW) * 1.12
        let amtStructure = master * (wStruct / sumW) * 1.12

        let edgeBlend = edgeAwareBlendMask(from: input, extent: extent, maskingPct: settings.sharpnessMaskingPct)
        let hlProtect = highlightProtectionMask(from: input, extent: extent)

        let combinedMask: CIImage? = {
            guard let e = edgeBlend, let h = hlProtect else { return edgeBlend ?? hlProtect }
            return multiplyRGBChannels(e, h, extent: extent)
        }()

        let neutralMask = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)).cropped(to: extent)
        let maskForPass = combinedMask ?? neutralMask

        var x = input
        x = unsharpLuminancePass(x, extent: extent, radius: radiusStructure, amount: amtStructure, threshold: tStruct, modulation: maskForPass)
        x = unsharpLuminancePass(x, extent: extent, radius: radiusEdge, amount: amtEdge, threshold: tEdge, modulation: maskForPass)
        x = unsharpLuminancePass(x, extent: extent, radius: radiusDetail, amount: amtDetail, threshold: tDetail, modulation: maskForPass)
        return x
    }

    // MARK: - USM luminance (Rec.709 linéaire), recombination par échelle — évite la dérive / assombrissement de l’USM RVB additif.

    private static let usmLuminanceKernel: CIColorKernel? = {
        let src = """
        kernel vec4 usmLuma(__sample orig, __sample blurred, __sample mask, float amt, float thresh, float soft) {
            vec3 W = vec3(0.2126, 0.7152, 0.0722);
            float Y = dot(max(orig.rgb, vec3(0.0)), W);
            float Yb = dot(max(blurred.rgb, vec3(0.0)), W);
            float d = Y - Yb;
            float a = abs(d);
            float mPass = smoothstep(thresh - soft, thresh + soft * 2.5, a);
            float modM = dot(mask.rgb, vec3(0.33333));
            modM = clamp(modM, 0.0, 1.0);
            float delta = amt * mPass * modM * d;
            float Y2 = max(Y + delta, 1.0e-6);
            float denom = max(Y, 1.0e-5);
            float sc = Y2 / denom;
            sc = clamp(sc, 0.2, 3.0);
            return vec4(max(orig.rgb * sc, vec3(0.0)), orig.a);
        }
        """
        return CIColorKernel(source: src)
    }()

    private static func unsharpLuminancePass(
        _ input: CIImage,
        extent: CGRect,
        radius: CGFloat,
        amount: Double,
        threshold: Double,
        modulation: CIImage
    ) -> CIImage {
        guard amount > 1e-6 else { return input }
        guard let blurred = gaussianBlur(input, radius: radius, extent: extent) else { return input }
        guard let k = usmLuminanceKernel else { return input }
        let soft = 0.0009
        return k.apply(
            extent: extent,
            roiCallback: { _, r in r },
            arguments: [
                input,
                blurred,
                modulation,
                NSNumber(value: amount),
                NSNumber(value: threshold),
                NSNumber(value: soft)
            ]
        ) ?? input
    }

    // MARK: - Masques

    /// `mix(1, edgeStrength, masking)` — zones plates préservées quand le masquage est élevé.
    private static func edgeAwareBlendMask(from input: CIImage, extent: CGRect, maskingPct: Double) -> CIImage? {
        let m = min(100, max(0, maskingPct)) / 100
        guard m > 0.012 else { return nil }

        guard let yMono = linearRec709AsGrayRGB(input) else { return nil }
        let wH: [CGFloat] = [-1, 0, 1, -2, 0, 2, -1, 0, 1]
        let wV: [CGFloat] = [-1, -2, -1, 0, 0, 0, 1, 2, 1]

        guard let hGray = convolution3x3(yMono, weights: wH, bias: 0.5, extent: extent),
              let vGray = convolution3x3(yMono, weights: wV, bias: 0.5, extent: extent),
              let packR = isolateToRed(hGray),
              let packG = isolateToGreen(vGray),
              let packed = addition(packR, packG, extent: extent) else {
            return fallbackFlatMask(from: yMono, extent: extent, maskingStrength: m)
        }

        let mag = DevelopPreviewKernels.applySobelMagnitudePacked(to: packed, extent: extent)

        guard let mono = CIFilter(name: "CIColorControls") else { return nil }
        mono.setValue(mag, forKey: kCIInputImageKey)
        mono.setValue(0.0, forKey: kCIInputSaturationKey)
        mono.setValue(1.38 + m * 1.12, forKey: kCIInputContrastKey)
        mono.setValue(0.04, forKey: kCIInputBrightnessKey)
        guard let boosted = mono.outputImage?.cropped(to: extent) else { return nil }

        guard let soften = CIFilter(name: "CIGaussianBlur") else { return boosted }
        soften.setValue(boosted, forKey: kCIInputImageKey)
        soften.setValue(0.95 + m * 2.2, forKey: kCIInputRadiusKey)
        guard let edge01 = soften.outputImage?.cropped(to: extent) else { return nil }

        return mixOneWithGray(edge: edge01, strength: m, extent: extent)
    }

    private static func fallbackFlatMask(from luminanceGray: CIImage, extent: CGRect, maskingStrength: Double) -> CIImage? {
        guard maskingStrength > 0.02 else { return nil }
        let blurR = max(1.2, 5 - maskingStrength * 3.2)
        guard let blur = CIFilter(name: "CIGaussianBlur") else { return nil }
        blur.setValue(luminanceGray, forKey: kCIInputImageKey)
        blur.setValue(blurR, forKey: kCIInputRadiusKey)
        guard let lowFreq = blur.outputImage?.cropped(to: extent) else { return nil }

        guard let diff = CIFilter(name: "CIDifferenceBlendMode") else { return nil }
        diff.setValue(luminanceGray, forKey: kCIInputImageKey)
        diff.setValue(lowFreq, forKey: kCIInputBackgroundImageKey)
        guard let edgesRaw = diff.outputImage else { return nil }

        guard let mono = CIFilter(name: "CIColorControls") else { return nil }
        mono.setValue(edgesRaw, forKey: kCIInputImageKey)
        mono.setValue(0.0, forKey: kCIInputSaturationKey)
        mono.setValue(1.75 + maskingStrength * 1.05, forKey: kCIInputContrastKey)
        mono.setValue(0.04, forKey: kCIInputBrightnessKey)
        guard let boosted = mono.outputImage else { return nil }

        guard let soften = CIFilter(name: "CIGaussianBlur") else { return boosted }
        soften.setValue(boosted, forKey: kCIInputImageKey)
        soften.setValue(1.05 + maskingStrength * 2.1, forKey: kCIInputRadiusKey)
        guard let edge01 = soften.outputImage?.cropped(to: extent) else { return nil }
        return mixOneWithGray(edge: edge01, strength: maskingStrength, extent: extent)
    }

    private static let highlightProtectionKernel: CIColorKernel? = {
        let src = """
        kernel vec4 hlProtect(__sample s) {
            float Y = dot(max(s.rgb, vec3(0.0)), vec3(0.2126, 0.7152, 0.0722));
            float k = 1.0 - smoothstep(0.66, 0.98, Y);
            return vec4(k, k, k, 1.0);
        }
        """
        return CIColorKernel(source: src)
    }()

    private static func highlightProtectionMask(from input: CIImage, extent: CGRect) -> CIImage? {
        guard let k = highlightProtectionKernel else { return nil }
        return k.apply(extent: extent, roiCallback: { _, r in r }, arguments: [input])
    }

    /// `mix(1, edge, strength)` sur la luminance du masque d’arête.
    private static let mixEdgeKernel: CIColorKernel? = {
        let src = """
        kernel vec4 mixEdge(__sample edge, float strength) {
            float e = dot(edge.rgb, vec3(0.33333));
            float o = mix(1.0, e, strength);
            return vec4(o, o, o, 1.0);
        }
        """
        return CIColorKernel(source: src)
    }()

    private static func mixOneWithGray(edge: CIImage, strength: Double, extent: CGRect) -> CIImage? {
        guard let k = mixEdgeKernel else { return edge }
        return k.apply(extent: extent, roiCallback: { _, r in r }, arguments: [edge, NSNumber(value: strength)])
    }

    // MARK: - CI helpers

    private static func linearRec709AsGrayRGB(_ input: CIImage) -> CIImage? {
        guard let m = CIFilter(name: "CIColorMatrix") else { return nil }
        m.setValue(input, forKey: kCIInputImageKey)
        let y = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
        m.setValue(y, forKey: "inputRVector")
        m.setValue(y, forKey: "inputGVector")
        m.setValue(y, forKey: "inputBVector")
        m.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        return m.outputImage
    }

    private static func gaussianBlur(_ input: CIImage, radius: CGFloat, extent: CGRect) -> CIImage? {
        guard let f = CIFilter(name: "CIGaussianBlur") else { return nil }
        f.setValue(input, forKey: kCIInputImageKey)
        f.setValue(radius, forKey: kCIInputRadiusKey)
        return f.outputImage?.cropped(to: extent)
    }

    private static func multiplyRGBChannels(_ a: CIImage, _ b: CIImage, extent: CGRect) -> CIImage? {
        guard let m = CIFilter(name: "CIMultiplyCompositing") else { return nil }
        m.setValue(a, forKey: kCIInputImageKey)
        m.setValue(b, forKey: kCIInputBackgroundImageKey)
        return m.outputImage?.cropped(to: extent)
    }

    private static func addition(_ hi: CIImage, _ lo: CIImage, extent: CGRect) -> CIImage? {
        guard let add = CIFilter(name: "CIAdditionCompositing") else { return nil }
        add.setValue(hi, forKey: kCIInputImageKey)
        add.setValue(lo, forKey: kCIInputBackgroundImageKey)
        return add.outputImage?.cropped(to: extent)
    }

    private static func convolution3x3(_ input: CIImage, weights: [CGFloat], bias: CGFloat, extent: CGRect) -> CIImage? {
        guard weights.count == 9,
              let f = CIFilter(name: "CIConvolution3X3") else { return nil }
        f.setValue(input, forKey: kCIInputImageKey)
        f.setValue(CIVector(values: weights, count: 9), forKey: "inputWeights")
        f.setValue(bias as NSNumber, forKey: "inputBias")
        return f.outputImage?.cropped(to: extent)
    }

    private static func isolateToRed(_ gray: CIImage) -> CIImage? {
        guard let m = CIFilter(name: "CIColorMatrix") else { return nil }
        m.setValue(gray, forKey: kCIInputImageKey)
        m.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
        m.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
        m.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
        m.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        return m.outputImage
    }

    private static func isolateToGreen(_ gray: CIImage) -> CIImage? {
        guard let m = CIFilter(name: "CIColorMatrix") else { return nil }
        m.setValue(gray, forKey: kCIInputImageKey)
        m.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
        m.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputGVector")
        m.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
        m.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        return m.outputImage
    }
}
