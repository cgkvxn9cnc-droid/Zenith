//
//  DevelopCropPipeline.swift
//  Zenith
//

import CoreImage

/// Rotation / retournements / recadrage Core Image — ordre : pivot centre → retournements → crop normalisé sur l’étendue résultante.
nonisolated enum DevelopCropPipeline {

    /// Redressement ± flip sans découpe (aperçu pendant l’outil recadrage avec `applyCrop: false`).
    nonisolated static func applyOrientationOnly(to image: CIImage, settings: DevelopSettings) -> CIImage {
        let crop = CropState(from: settings)
        guard abs(crop.angleRadians) > 1e-6 || crop.flipHorizontal || crop.flipVertical else {
            return image
        }
        return transformed(image: image, angleRadians: crop.angleRadians, flipH: crop.flipHorizontal, flipV: crop.flipVertical)
    }

    /// Orientation complète + recadrage normalisé (export et pipeline principal).
    nonisolated static func applyOrientAndCrop(to image: CIImage, settings: DevelopSettings) -> CIImage {
        let crop = CropState(from: settings)
        let oriented = transformed(image: image, angleRadians: crop.angleRadians, flipH: crop.flipHorizontal, flipV: crop.flipVertical)
        return cropNormalizedImage(oriented, normalizedRect: crop.rect)
    }

    nonisolated static func applyCrop(source: CIImage, crop: CropState) -> CIImage {
        let oriented = transformed(image: source, angleRadians: crop.angleRadians, flipH: crop.flipHorizontal, flipV: crop.flipVertical)
        return cropNormalizedImage(oriented, normalizedRect: crop.rect)
    }

    // MARK: - Internals

    private nonisolated static func transformed(
        image: CIImage,
        angleRadians: Double,
        flipH: Bool,
        flipV: Bool
    ) -> CIImage {
        let e = image.extent
        let cx = e.midX
        let cy = e.midY

        var t = CGAffineTransform(translationX: cx, y: cy)
            .rotated(by: CGFloat(angleRadians))
            .translatedBy(x: -cx, y: -cy)

        if flipH {
            let fh = CGAffineTransform(translationX: cx, y: cy)
                .scaledBy(x: -1, y: 1)
                .translatedBy(x: -cx, y: -cy)
            t = t.concatenating(fh)
        }
        if flipV {
            let fv = CGAffineTransform(translationX: cx, y: cy)
                .scaledBy(x: 1, y: -1)
                .translatedBy(x: -cx, y: -cy)
            t = t.concatenating(fv)
        }

        return image.transformed(by: t)
    }

    private nonisolated static func cropNormalizedImage(_ image: CIImage, normalizedRect: CGRect) -> CIImage {
        let nx = Double(normalizedRect.origin.x)
        let ny = Double(normalizedRect.origin.y)
        let nw = Double(normalizedRect.width)
        let nh = Double(normalizedRect.height)
        guard nw > 1e-8, nh > 1e-8 else { return image }

        let re = image.extent
        let cropPx = CGRect(
            x: re.minX + CGFloat(nx) * re.width,
            y: re.minY + CGFloat(ny) * re.height,
            width: CGFloat(nw) * re.width,
            height: CGFloat(nh) * re.height
        ).intersection(re)

        guard cropPx.width > 1.5, cropPx.height > 1.5 else { return image }
        return image.cropped(to: cropPx)
    }
}
