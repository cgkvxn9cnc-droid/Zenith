//
//  DevelopCropGeometry.swift
//  Zenith
//

import CoreGraphics
import Foundation

/// Conversion rectangle pixels (repère affichage : haut-gauche, Y vers le bas) ↔ fractions `DevelopSettings`.
enum DevelopCropGeometry {
    static let minimumCropFraction: CGFloat = 0.04

    static func pixelCropRect(from settings: DevelopSettings, imageWidth iw: CGFloat, imageHeight ih: CGFloat) -> CGRect {
        guard iw > 0, ih > 0 else { return .zero }
        let l = CGFloat(settings.cropLeft)
        let r = CGFloat(settings.cropRight)
        let tModel = CGFloat(settings.cropTop)
        let bModel = CGFloat(settings.cropBottom)
        let cw = (1 - l - r) * iw
        let ch = (1 - tModel - bModel) * ih
        let cx = l * iw
        let cy = bModel * ih
        return CGRect(x: cx, y: cy, width: max(1, cw), height: max(1, ch))
    }

    static func applyPixelCrop(_ rect: CGRect, imageWidth iw: CGFloat, imageHeight ih: CGFloat, to settings: inout DevelopSettings) {
        guard iw > 1, ih > 1 else { return }
        var r = rect.standardized.intersection(CGRect(x: 0, y: 0, width: iw, height: ih))
        let minSide = minimumCropFraction * min(iw, ih)
        if r.width < minSide { r.size.width = min(minSide, iw) }
        if r.height < minSide { r.size.height = min(minSide, ih) }
        r = r.standardized.intersection(CGRect(x: 0, y: 0, width: iw, height: ih))
        settings.cropLeft = Double(r.minX / iw)
        settings.cropRight = Double((iw - r.maxX) / iw)
        settings.cropTop = Double((ih - r.maxY) / ih)
        settings.cropBottom = Double(r.minY / ih)
        settings.cropLeft = min(0.49, max(0, settings.cropLeft))
        settings.cropRight = min(0.49, max(0, settings.cropRight))
        settings.cropTop = min(0.49, max(0, settings.cropTop))
        settings.cropBottom = min(0.49, max(0, settings.cropBottom))
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

    static func clampPixelCrop(_ rect: CGRect, imageWidth iw: CGFloat, imageHeight ih: CGFloat) -> CGRect {
        var r = rect.standardized.intersection(CGRect(x: 0, y: 0, width: iw, height: ih))
        let minSide = minimumCropFraction * min(iw, ih)
        if r.width < minSide { r.size.width = min(minSide, iw) }
        if r.height < minSide { r.size.height = min(minSide, ih) }
        return r.standardized.intersection(CGRect(x: 0, y: 0, width: iw, height: ih))
    }

    static func translateCrop(_ rect: CGRect, delta dx: CGFloat, dy: CGFloat, imageWidth iw: CGFloat, imageHeight ih: CGFloat) -> CGRect {
        var r = rect.standardized
        r.origin.x += dx
        r.origin.y += dy
        if r.minX < 0 { r.origin.x = 0 }
        if r.minY < 0 { r.origin.y = 0 }
        if r.maxX > iw { r.origin.x = iw - r.width }
        if r.maxY > ih { r.origin.y = ih - r.height }
        return clampPixelCrop(r, imageWidth: iw, imageHeight: ih)
    }

    private static func minimumSidePixels(_ iw: CGFloat, _ ih: CGFloat) -> CGFloat {
        minimumCropFraction * min(iw, ih)
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

    /// Redimensionne depuis un coin ; `finger` en coordonnées pixels image (haut-gauche).
    static func resizeByCorner(
        _ corner: ActiveCropCorner,
        current: CGRect,
        finger: CGPoint,
        aspectWidthOverHeight: CGFloat?,
        imageWidth iw: CGFloat,
        imageHeight ih: CGFloat
    ) -> CGRect {
        let r = current.standardized
        let m = minimumSidePixels(iw, ih)
        switch corner {
        case .bottomRight:
            let tl = CGPoint(x: r.minX, y: r.minY)
            let bx = min(iw, max(finger.x, tl.x + m))
            let by = min(ih, max(finger.y, tl.y + m))
            var w = bx - tl.x
            var h = by - tl.y
            if let a = aspectWidthOverHeight, a > 0 {
                (w, h) = pickSize(width: w, height: h, aspect: a)
            }
            return clampPixelCrop(CGRect(origin: tl, size: CGSize(width: w, height: h)), imageWidth: iw, imageHeight: ih)

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
            return clampPixelCrop(CGRect(origin: CGPoint(x: ox, y: oy), size: CGSize(width: w, height: h)), imageWidth: iw, imageHeight: ih)

        case .topRight:
            let bl = CGPoint(x: r.minX, y: r.maxY)
            let trX = min(iw, max(finger.x, bl.x + m))
            let trY = max(0, min(finger.y, bl.y - m))
            var w = trX - bl.x
            var h = bl.y - trY
            if let a = aspectWidthOverHeight, a > 0 {
                (w, h) = pickSize(width: w, height: h, aspect: a)
            }
            let ox = bl.x
            let oy = bl.y - h
            return clampPixelCrop(CGRect(origin: CGPoint(x: ox, y: oy), size: CGSize(width: w, height: h)), imageWidth: iw, imageHeight: ih)

        case .bottomLeft:
            let tr = CGPoint(x: r.maxX, y: r.minY)
            let blX = max(0, min(finger.x, tr.x - m))
            let blY = min(ih, max(finger.y, tr.y + m))
            var w = tr.x - blX
            var h = blY - tr.y
            if let a = aspectWidthOverHeight, a > 0 {
                (w, h) = pickSize(width: w, height: h, aspect: a)
            }
            let ox = tr.x - w
            let oy = tr.y
            return clampPixelCrop(CGRect(origin: CGPoint(x: ox, y: oy), size: CGSize(width: w, height: h)), imageWidth: iw, imageHeight: ih)
        }
    }
}
