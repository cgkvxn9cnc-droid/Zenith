//
//  HorizonStraightenService.swift
//  Zenith
//

import CoreImage
import Metal
import Vision

/// Détection d’horizon via Vision (`VNDetectHorizonRequest`) pour pré‑remplir le redressement.
nonisolated enum HorizonStraightenService {
    /// Contexte CI **dédié** à l’échantillon Vision (évite de partager `DevelopPreviewRenderer.sharedContext` avec le cache d’aperçu / `pipelineLock`).
    private static let visionSampleContext: CIContext = {
        var options: [CIContextOption: Any] = [:]
        options[.useSoftwareRenderer] = NSNumber(value: false)
        options[.cacheIntermediates] = NSNumber(value: false)
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

    /// Angle en **degrés** pour `DevelopSettings.straightenAngle` (clamp ±45 côté service ; l’UI utilise la même plage).
    nonisolated static func estimateStraightenDegrees(ciImage: CIImage) async -> Double? {
        let extent = ciImage.extent
        guard extent.width > 2, extent.height > 2,
              let ir = DevelopPreviewRenderer.integralRectForRasterization(extent),
              let cg = visionSampleContext.createCGImage(ciImage, from: ir) else {
            return nil
        }

        await Task.yield()
        return await Task.detached(priority: .userInitiated) {
            let request = VNDetectHorizonRequest()
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do {
                try handler.perform([request])
            } catch {
                return nil
            }
            guard let obs = request.results?.first as? VNHorizonObservation else {
                return nil
            }
            let t = obs.transform
            let radians = atan2(Double(t.b), Double(t.a))
            let degrees = -radians * 180 / .pi
            return max(-45, min(45, degrees))
        }.value
    }
}
