//
//  DevelopCropGeometry.swift
//  Zenith
//

import CoreGraphics
import Foundation

/// Géométrie du recadrage : coordonnées **pixels** dans la toile axis‑alignée **après** rotation (`rotatedCanvasPixelSize`),
/// avec origine **bas‑gauche** comme Core Image. La conversion vers SwiftUI (Y depuis le haut) est faite dans l’overlay.
enum DevelopCropGeometry {
    /// Constante pure : `nonisolated` pour les helpers de décodage / crop hors MainActor.
    nonisolated static let minimumCropFraction: CGFloat = 0.04

    /// Boîte englobante axis‑alignée d’une image `W×H` pivotée de `angleDegrees` (voir pipeline CI).
    static func rotatedCanvasPixelSize(imageWidth W: CGFloat, imageHeight H: CGFloat, angleDegrees: Double) -> CGSize {
        guard W > 0, H > 0 else { return CGSize(width: 1, height: 1) }
        let rad = angleDegrees * .pi / 180
        let c = abs(cos(rad))
        let s = abs(sin(rad))
        return CGSize(width: W * c + H * s, height: W * s + H * c)
    }

    /// Rectangle de crop en pixels (origine bas‑gauche, toile post‑rotation).
    static func pixelCropRectCanvasBL(from settings: DevelopSettings, imageWidth iw: CGFloat, imageHeight ih: CGFloat) -> CGRect {
        let canvas = rotatedCanvasPixelSize(imageWidth: iw, imageHeight: ih, angleDegrees: settings.straightenAngle)
        let cw = canvas.width
        let ch = canvas.height
        guard cw > 0, ch > 0 else { return .zero }

        let nx = CGFloat(settings.cropNormalizedOriginX)
        let ny = CGFloat(settings.cropNormalizedOriginY)
        let nw = CGFloat(settings.cropNormalizedWidth)
        let nh = CGFloat(settings.cropNormalizedHeight)

        let x = nx * cw
        let y = ny * ch
        let w = max(1, nw * cw)
        let h = max(1, nh * ch)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Alias historique — même repère bas‑gauche sur la toile post‑rotation (`iw`×`ih` = taille fichier source).
    static func pixelCropRect(from settings: DevelopSettings, imageWidth iw: CGFloat, imageHeight ih: CGFloat) -> CGRect {
        pixelCropRectCanvasBL(from: settings, imageWidth: iw, imageHeight: ih)
    }

    static func applyPixelCrop(_ rectCanvasBL: CGRect, imageWidth iw: CGFloat, imageHeight ih: CGFloat, to settings: inout DevelopSettings) {
        let canvas = rotatedCanvasPixelSize(imageWidth: iw, imageHeight: ih, angleDegrees: settings.straightenAngle)
        let cw = canvas.width
        let ch = canvas.height
        guard cw > 1, ch > 1 else { return }

        var r = rectCanvasBL.standardized.intersection(CGRect(x: 0, y: 0, width: cw, height: ch))
        let minSide = minimumCropFraction * min(cw, ch)
        if r.width < minSide {
            r.size.width = min(minSide, cw)
            if r.maxX > cw { r.origin.x = max(0, cw - r.width) }
        }
        if r.height < minSide {
            r.size.height = min(minSide, ch)
            if r.maxY > ch { r.origin.y = max(0, ch - r.height) }
        }
        r = r.standardized.intersection(CGRect(x: 0, y: 0, width: cw, height: ch))

        settings.cropNormalizedOriginX = Double(r.minX / cw)
        settings.cropNormalizedOriginY = Double(r.minY / ch)
        settings.cropNormalizedWidth = Double(r.width / cw)
        settings.cropNormalizedHeight = Double(r.height / ch)

        clampNormalizedCrop(in: &settings)
        syncLegacyMarginsFromNormalized(&settings)
    }

    nonisolated static func clampNormalizedCrop(in settings: inout DevelopSettings) {
        let ε = 1e-6
        let minNorm = Double(minimumCropFraction)

        func clamp01(_ x: Double) -> Double {
            if !x.isFinite { return 0 }
            return max(0, min(1, x))
        }

        var nx = clamp01(settings.cropNormalizedOriginX)
        var ny = clamp01(settings.cropNormalizedOriginY)

        var nw = settings.cropNormalizedWidth
        var nh = settings.cropNormalizedHeight
        if !nw.isFinite || nw <= 0 { nw = 1 }
        if !nh.isFinite || nh <= 0 { nh = 1 }

        // Laisse au moins `minNorm` de largeur/hauteur disponible depuis l’origine.
        if 1 - nx < minNorm { nx = max(0, 1 - minNorm) }
        if 1 - ny < minNorm { ny = max(0, 1 - minNorm) }

        nw = max(minNorm, min(nw, 1 - nx))
        nh = max(minNorm, min(nh, 1 - ny))

        settings.cropNormalizedOriginX = nx
        settings.cropNormalizedOriginY = ny
        settings.cropNormalizedWidth = max(ε, nw)
        settings.cropNormalizedHeight = max(ε, nh)
    }

    /// Garde la compatibilité avec les champs `cropLeft` … utilisés ailleurs / anciennes données.
    nonisolated static func syncLegacyMarginsFromNormalized(_ settings: inout DevelopSettings) {
        let nx = settings.cropNormalizedOriginX
        let ny = settings.cropNormalizedOriginY
        let nw = settings.cropNormalizedWidth
        let nh = settings.cropNormalizedHeight
        func clampMargin(_ x: Double) -> Double {
            if !x.isFinite { return 0 }
            return max(0, min(1, x))
        }
        settings.cropLeft = clampMargin(nx)
        settings.cropBottom = clampMargin(ny)
        settings.cropRight = clampMargin(1 - nx - nw)
        settings.cropTop = clampMargin(1 - ny - nh)
    }

    /// Initialise les champs normalisés à partir des marges legacy (repère bas‑gauche pour `cropBottom` / `cropTop`).
    nonisolated static func migrateNormalizedCropFromLegacyMargins(_ settings: inout DevelopSettings) {
        let l = max(0, settings.cropLeft)
        let r = max(0, settings.cropRight)
        let t = max(0, settings.cropTop)
        let b = max(0, settings.cropBottom)
        guard l + r < 0.999, t + b < 0.999 else {
            settings.cropNormalizedOriginX = 0
            settings.cropNormalizedOriginY = 0
            settings.cropNormalizedWidth = 1
            settings.cropNormalizedHeight = 1
            clampNormalizedCrop(in: &settings)
            return
        }
        settings.cropNormalizedOriginX = l
        settings.cropNormalizedOriginY = b
        settings.cropNormalizedWidth = max(1e-6, 1 - l - r)
        settings.cropNormalizedHeight = max(1e-6, 1 - t - b)
        clampNormalizedCrop(in: &settings)
    }

    static func maxCenteredRect(imageWidth iw: CGFloat, imageHeight ih: CGFloat, widthOverHeight: CGFloat?) -> CGRect {
        guard iw > 1, ih > 1 else {
            return CGRect(x: 0, y: 0, width: max(1, iw), height: max(1, ih))
        }
        guard let ar = widthOverHeight, ar > 0 else {
            return CGRect(x: 0, y: 0, width: iw, height: ih)
        }
        var cw = iw
        var ch = cw / ar
        if ch > ih {
            ch = ih
            cw = ch * ar
        }
        let cx = (iw - cw) * 0.5
        let cy = (ih - ch) * 0.5
        return CGRect(x: cx, y: cy, width: cw, height: ch)
    }

    static func clampPixelCropCanvasBL(_ rect: CGRect, canvasWidth cw: CGFloat, canvasHeight ch: CGFloat) -> CGRect {
        var r = rect.standardized.intersection(CGRect(x: 0, y: 0, width: cw, height: ch))
        let minSide = minimumCropFraction * min(cw, ch)
        if r.width < minSide { r.size.width = min(minSide, cw) }
        if r.height < minSide { r.size.height = min(minSide, ch) }
        return r.standardized.intersection(CGRect(x: 0, y: 0, width: cw, height: ch))
    }

    static func translateCrop(_ rect: CGRect, delta dx: CGFloat, dy: CGFloat, canvasWidth cw: CGFloat, canvasHeight ch: CGFloat) -> CGRect {
        var r = rect.standardized
        r.origin.x += dx
        r.origin.y += dy
        if r.minX < 0 { r.origin.x = 0 }
        if r.minY < 0 { r.origin.y = 0 }
        if r.maxX > cw { r.origin.x = cw - r.width }
        if r.maxY > ch { r.origin.y = ch - r.height }
        return clampPixelCropCanvasBL(r, canvasWidth: cw, canvasHeight: ch)
    }

    private static func minimumSidePixels(_ cw: CGFloat, _ ch: CGFloat) -> CGFloat {
        minimumCropFraction * min(cw, ch)
    }

    private static func pickSize(width w: CGFloat, height h: CGFloat, aspect a: CGFloat) -> (CGFloat, CGFloat) {
        let s1h = w / a
        let s2w = h * a
        if w * s1h >= s2w * h {
            return (w, s1h)
        }
        return (s2w, h)
    }

    enum ActiveCropCorner: Hashable {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    enum ActiveCropEdge: Hashable {
        case top
        case bottom
        case left
        case right
    }

    /// Redimensionne depuis un coin ; `finger` en coordonnées **bas‑gauche** sur la toile.
    static func resizeByCorner(
        _ corner: ActiveCropCorner,
        current: CGRect,
        finger: CGPoint,
        aspectWidthOverHeight: CGFloat?,
        canvasWidth cw: CGFloat,
        canvasHeight ch: CGFloat
    ) -> CGRect {
        let r = current.standardized
        let m = minimumSidePixels(cw, ch)
        switch corner {
        case .bottomRight:
            let tl = CGPoint(x: r.minX, y: r.minY)
            let bx = min(cw, max(finger.x, tl.x + m))
            let by = min(ch, max(finger.y, tl.y + m))
            var w = bx - tl.x
            var h = by - tl.y
            if let a = aspectWidthOverHeight, a > 0 {
                (w, h) = pickSize(width: w, height: h, aspect: a)
            }
            return clampPixelCropCanvasBL(CGRect(origin: tl, size: CGSize(width: w, height: h)), canvasWidth: cw, canvasHeight: ch)

        case .topLeft:
            let br = CGPoint(x: r.maxX, y: r.maxY)
            let tx = max(0, min(finger.x, br.x - m))
            let ty = max(0, min(finger.y, br.y - m))
            var w = br.x - tx
            var h = br.y - ty
            if let a = aspectWidthOverHeight, a > 0 {
                (w, h) = pickSize(width: w, height: h, aspect: a)
            }
            let ox = br.x - w
            let oy = br.y - h
            return clampPixelCropCanvasBL(CGRect(origin: CGPoint(x: ox, y: oy), size: CGSize(width: w, height: h)), canvasWidth: cw, canvasHeight: ch)

        case .topRight:
            let bl = CGPoint(x: r.minX, y: r.maxY)
            let trX = min(cw, max(finger.x, bl.x + m))
            let trY = max(0, min(finger.y, bl.y - m))
            var w = trX - bl.x
            var h = bl.y - trY
            if let a = aspectWidthOverHeight, a > 0 {
                (w, h) = pickSize(width: w, height: h, aspect: a)
            }
            let ox = bl.x
            let oy = bl.y - h
            return clampPixelCropCanvasBL(CGRect(origin: CGPoint(x: ox, y: oy), size: CGSize(width: w, height: h)), canvasWidth: cw, canvasHeight: ch)

        case .bottomLeft:
            let tr = CGPoint(x: r.maxX, y: r.minY)
            let blX = max(0, min(finger.x, tr.x - m))
            let blY = min(ch, max(finger.y, tr.y + m))
            var w = tr.x - blX
            var h = blY - tr.y
            if let a = aspectWidthOverHeight, a > 0 {
                (w, h) = pickSize(width: w, height: h, aspect: a)
            }
            let ox = tr.x - w
            let oy = tr.y
            return clampPixelCropCanvasBL(CGRect(origin: CGPoint(x: ox, y: oy), size: CGSize(width: w, height: h)), canvasWidth: cw, canvasHeight: ch)
        }
    }

    /// Poignées milieu de côté — repère bas‑gauche.
    static func resizeByEdge(
        _ edge: ActiveCropEdge,
        current: CGRect,
        finger: CGPoint,
        aspectWidthOverHeight: CGFloat?,
        canvasWidth cw: CGFloat,
        canvasHeight ch: CGFloat
    ) -> CGRect {
        let r = current.standardized
        let m = minimumSidePixels(cw, ch)
        switch edge {
        case .right:
            let tl = CGPoint(x: r.minX, y: r.minY)
            let newW = min(cw - tl.x, max(m, finger.x - tl.x))
            var w = newW
            var h = r.height
            if let a = aspectWidthOverHeight, a > 0 {
                h = w / a
                if tl.y + h > ch { h = ch - tl.y }
                w = h * a
            }
            return clampPixelCropCanvasBL(CGRect(origin: tl, size: CGSize(width: w, height: h)), canvasWidth: cw, canvasHeight: ch)

        case .left:
            let tr = CGPoint(x: r.maxX, y: r.maxY)
            let newMinX = max(0, min(finger.x, tr.x - m))
            var w = tr.x - newMinX
            var h = r.height
            if let a = aspectWidthOverHeight, a > 0 {
                h = w / a
                if tr.y - h < 0 { h = tr.y }
                w = h * a
            }
            let ox = tr.x - w
            let oy = r.minY
            return clampPixelCropCanvasBL(CGRect(origin: CGPoint(x: ox, y: oy), size: CGSize(width: w, height: h)), canvasWidth: cw, canvasHeight: ch)

        case .top:
            let bl = CGPoint(x: r.minX, y: r.minY)
            let newMaxY = min(ch, max(bl.y + m, finger.y))
            var h = newMaxY - bl.y
            var w = r.width
            if let a = aspectWidthOverHeight, a > 0 {
                w = h * a
                if bl.x + w > cw { w = cw - bl.x }
                h = w / a
            }
            return clampPixelCropCanvasBL(CGRect(origin: bl, size: CGSize(width: w, height: h)), canvasWidth: cw, canvasHeight: ch)

        case .bottom:
            let anchorTopY = r.maxY
            let newMinY = max(0, min(finger.y, anchorTopY - m))
            var h = anchorTopY - newMinY
            var w = r.width
            if let a = aspectWidthOverHeight, a > 0 {
                w = h * a
                if r.minX + w > cw { w = cw - r.minX }
                h = w / a
            }
            let ox = r.minX
            let oy = newMinY
            return clampPixelCropCanvasBL(CGRect(origin: CGPoint(x: ox, y: oy), size: CGSize(width: w, height: h)), canvasWidth: cw, canvasHeight: ch)
        }
    }
}
