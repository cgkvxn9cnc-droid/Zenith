//
//  ZenithSourceColorNormalizer.swift
//  Zenith
//
//  Conversion des sources bitmap vers l’espace de travail linéaire du CIContext Develop.
//

import CoreImage
import Foundation
import ImageIO

nonisolated enum ZenithSourceColorNormalizer {

    /// Prépare une `CIImage` issue du disque pour `developedCIImage(from:…)` : RVB taggé / assumé → linear working ; CMJN → RVB approximatif.
    /// Les RAW (pas de description bitmap) sont laissés tels quels (sortie `CIRAWFilter`).
    static func normalizeForDevelopPipeline(image: CIImage, url: URL) -> CIImage {
        guard let desc = ColorProfileReader.describeIfBitmap(url: url) else {
            return image
        }

        if desc.isCMYK {
            if let rgb = convertCMYKAssetToLinearWorkingRGB(url: url) {
                return rgb
            }
            return image
        }

        let assumed = ZenithAssumedRGBProfile.current
        let src = desc.effectiveSourceRGBColorSpace(assumed: assumed)
        return image.matchedToWorkingSpace(from: src) ?? image
    }

    /// Dessin `CGImage` CMJN → bitmap sRVB 8 bits puis passage en espace de travail CI (linéaire).
    private static func convertCMYKAssetToLinearWorkingRGB(url: URL) -> CIImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, opts as CFDictionary),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, opts as CFDictionary)
        else {
            return nil
        }
        let w = cg.width
        let h = cg.height
        guard let rgb = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let rowBytes = w * 4
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: rowBytes,
            space: rgb,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let outCG = ctx.makeImage() else { return nil }
        let ci = CIImage(cgImage: outCG)
        return ci.matchedToWorkingSpace(from: rgb) ?? ci
    }
}
