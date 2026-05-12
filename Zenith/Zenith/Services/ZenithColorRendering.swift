//
//  ZenithColorRendering.swift
//  Zenith
//
//  Rasterisation finale de l’aperçu Develop : espace de sortie sRVB ou Display P3 selon les réglages.
//

import CoreGraphics
import CoreImage

nonisolated enum ZenithColorRendering: Sendable {

    nonisolated static func previewOutputColorSpace() -> CGColorSpace {
        if ZenithColorPreferences.useDisplayP3PreviewOutput,
           let p3 = CGColorSpace(name: CGColorSpace.displayP3) {
            return p3
        }
        return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    /// Crée un `CGImage` pour l’UI ; tente d’abord 16 bits puis 8 bits dans l’espace de sortie choisi.
    nonisolated static func createDevelopPreviewCGImage(context: CIContext, output: CIImage, from rect: CGRect) -> CGImage? {
        let cs = previewOutputColorSpace()
        if let cg = context.createCGImage(output, from: rect, format: .RGBA16, colorSpace: cs) {
            return cg
        }
        if let cg = context.createCGImage(output, from: rect, format: .RGBA8, colorSpace: cs) {
            return cg
        }
        return context.createCGImage(output, from: rect)
    }
}
