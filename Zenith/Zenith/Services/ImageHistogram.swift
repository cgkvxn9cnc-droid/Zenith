//
//  ImageHistogram.swift
//  Zenith
//

import CoreGraphics
import CoreImage

struct RGBLHistogramData: Sendable {
    var red: [Float]
    var green: [Float]
    var blue: [Float]
    var luminance: [Float]
    var showsShadowClipping: Bool
    var showsHighlightClipping: Bool

    static let flat: RGBLHistogramData = {
        let z = Array(repeating: Float(0), count: 256)
        return RGBLHistogramData(red: z, green: z, blue: z, luminance: z, showsShadowClipping: false, showsHighlightClipping: false)
    }()
}

enum ImageHistogram {
    private static let readContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Bins 0…255 normalisés (max = 1) pour la luminance perceptuelle.
    static func luminanceBins(from ciImage: CIImage, maxSampleSide: CGFloat = 512) -> [Float] {
        rgbLHistogram(from: ciImage, maxSampleSide: maxSampleSide).luminance
    }

    /// Histogrammes R, V, B et luminance superposables + heuristique de débouchage (style logiciels photo).
    static func rgbLHistogram(from ciImage: CIImage, maxSampleSide: CGFloat = 512) -> RGBLHistogramData {
        var img = ciImage
        let w0 = img.extent.width
        let h0 = img.extent.height
        let m = max(w0, h0)
        if m > maxSampleSide, m > 0 {
            let s = maxSampleSide / m
            img = img.transformed(by: CGAffineTransform(scaleX: s, y: s))
        }
        let extent = img.extent
        let integral = CGRect(
            x: floor(extent.origin.x),
            y: floor(extent.origin.y),
            width: max(1, ceil(extent.width)),
            height: max(1, ceil(extent.height))
        )
        guard integral.width.isFinite, integral.height.isFinite,
              let cg = readContext.createCGImage(img, from: integral) else {
            let z = Array(repeating: Float(0), count: 256)
            return RGBLHistogramData(red: z, green: z, blue: z, luminance: z, showsShadowClipping: false, showsHighlightClipping: false)
        }
        return rgbLHistogram(from: cg)
    }

    private static func rgbLHistogram(from cgImage: CGImage) -> RGBLHistogramData {
        let w = cgImage.width
        let h = cgImage.height
        var binsR = [Float](repeating: 0, count: 256)
        var binsG = [Float](repeating: 0, count: 256)
        var binsB = [Float](repeating: 0, count: 256)
        var binsL = [Float](repeating: 0, count: 256)
        let bytesPerPixel = 4
        let rowBytes = w * bytesPerPixel
        var data = [UInt8](repeating: 0, count: rowBytes * h)
        data.withUnsafeMutableBytes { raw in
            guard
                let ctx = CGContext(
                    data: raw.baseAddress,
                    width: w,
                    height: h,
                    bitsPerComponent: 8,
                    bytesPerRow: rowBytes,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else { return }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var validPixels = 0
        var shadowCount = 0
        var highlightCount = 0
        for i in stride(from: 0, to: data.count, by: 4) {
            let af = Float(data[i + 3]) / 255
            guard af > 0.001 else { continue }
            let r = Float(data[i]) / 255 / af
            let g = Float(data[i + 1]) / 255 / af
            let b = Float(data[i + 2]) / 255 / af
            let lum = 0.299 * r + 0.587 * g + 0.114 * b
            let iR = min(255, max(0, Int(r * 255)))
            let iG = min(255, max(0, Int(g * 255)))
            let iB = min(255, max(0, Int(b * 255)))
            let iL = min(255, max(0, Int(lum * 255)))
            binsR[iR] += 1
            binsG[iG] += 1
            binsB[iB] += 1
            binsL[iL] += 1
            validPixels += 1
            if iL == 0 { shadowCount += 1 }
            if iL == 255 { highlightCount += 1 }
        }
        normalize(&binsR)
        normalize(&binsG)
        normalize(&binsB)
        normalize(&binsL)
        let total = max(validPixels, 1)
        let shadowRatio = Double(shadowCount) / Double(total)
        let highlightRatio = Double(highlightCount) / Double(total)
        return RGBLHistogramData(
            red: binsR,
            green: binsG,
            blue: binsB,
            luminance: binsL,
            showsShadowClipping: shadowRatio > 0.0012,
            showsHighlightClipping: highlightRatio > 0.0012
        )
    }

    private static func normalize(_ bins: inout [Float]) {
        let maxB = bins.max() ?? 1
        guard maxB > 0 else { return }
        for j in 0 ..< 256 { bins[j] /= maxB }
    }
}
