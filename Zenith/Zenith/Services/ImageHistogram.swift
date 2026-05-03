//
//  ImageHistogram.swift
//  Zenith
//

import CoreGraphics
import CoreImage

enum ImageHistogram {
    private static let readContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Bins 0…255 normalisés (max = 1) pour la luminance perceptuelle.
    static func luminanceBins(from ciImage: CIImage, maxSampleSide: CGFloat = 512) -> [Float] {
        var img = ciImage
        let w0 = img.extent.width
        let h0 = img.extent.height
        let m = max(w0, h0)
        if m > maxSampleSide, m > 0 {
            let s = maxSampleSide / m
            img = img.transformed(by: CGAffineTransform(scaleX: s, y: s))
        }
        let extent = img.extent
        guard let cg = readContext.createCGImage(img, from: extent) else {
            return Array(repeating: 0, count: 256)
        }
        return luminanceBins(from: cg)
    }

    private static func luminanceBins(from cgImage: CGImage) -> [Float] {
        let w = cgImage.width
        let h = cgImage.height
        var bins = [Float](repeating: 0, count: 256)
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
        for i in stride(from: 0, to: data.count, by: 4) {
            let af = Float(data[i + 3]) / 255
            guard af > 0.001 else { continue }
            let r = Float(data[i]) / 255 / af
            let g = Float(data[i + 1]) / 255 / af
            let b = Float(data[i + 2]) / 255 / af
            let lum = 0.299 * r + 0.587 * g + 0.114 * b
            let idx = min(255, max(0, Int(lum * 255)))
            bins[idx] += 1
        }
        let maxB = bins.max() ?? 1
        if maxB > 0 {
            for j in 0 ..< 256 { bins[j] /= maxB }
        }
        return bins
    }
}
