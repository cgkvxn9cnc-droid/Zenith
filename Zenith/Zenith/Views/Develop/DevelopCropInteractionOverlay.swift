//
//  DevelopCropInteractionOverlay.swift
//  Zenith
//

import SwiftData
import SwiftUI

/// Recadrage type Lightroom : assombrissement, grille, poignées et déplacement.
struct DevelopCropInteractionOverlay: View {
    @Bindable var photo: PhotoRecord
    let viewportSize: CGSize
    let imageRect: CGRect
    let imagePixelSize: CGSize

    @Environment(\.modelContext) private var modelContext

    @State private var transientPixelCrop: CGRect?
    @State private var resizeStartRect: CGRect?
    @State private var panStartRect: CGRect?

    private var iw: CGFloat { max(1, imagePixelSize.width) }
    private var ih: CGFloat { max(1, imagePixelSize.height) }

    private var committedPixelCrop: CGRect {
        DevelopCropGeometry.pixelCropRect(from: photo.developSettings, imageWidth: iw, imageHeight: ih)
    }

    private var livePixelCrop: CGRect {
        transientPixelCrop ?? committedPixelCrop
    }

    private var lockedAspect: CGFloat? {
        let preset = DevelopCropAspectPreset(rawValue: photo.developSettings.cropAspectPresetRaw) ?? .free
        return preset.widthOverHeight(imageNaturalRatio: iw / ih)
    }

    var body: some View {
        ZStack {
            cropOutsideDim

            let vr = viewRect(for: livePixelCrop)
            Path { p in
                p.addRect(vr)
            }
            .stroke(Color.white.opacity(0.95), lineWidth: 1.2)
            .allowsHitTesting(false)

            cropRuleOfThirds(in: vr)

            Color.clear
                .frame(width: vr.width, height: vr.height)
                .position(x: vr.midX, y: vr.midY)
                .contentShape(Rectangle())
                .gesture(panGesture)

            ForEach([DevelopCropGeometry.ActiveCropCorner.topLeft, .topRight, .bottomLeft, .bottomRight], id: \.self) { corner in
                cropHandle
                    .position(cornerPoint(corner, viewRect: vr))
                    .gesture(cornerGesture(corner))
            }
        }
        .frame(width: viewportSize.width, height: viewportSize.height)
        .onChange(of: photo.developBlob) { _, _ in
            transientPixelCrop = nil
            resizeStartRect = nil
            panStartRect = nil
        }
    }

    private var cropOutsideDim: some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: viewportSize))
            path.addRect(viewRect(for: livePixelCrop))
        }
        .fill(Color.black.opacity(0.52), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
    }

    private func cropRuleOfThirds(in vr: CGRect) -> some View {
        Path { path in
            let x1 = vr.minX + vr.width / 3
            let x2 = vr.minX + vr.width * 2 / 3
            let y1 = vr.minY + vr.height / 3
            let y2 = vr.minY + vr.height * 2 / 3
            path.move(to: CGPoint(x: x1, y: vr.minY))
            path.addLine(to: CGPoint(x: x1, y: vr.maxY))
            path.move(to: CGPoint(x: x2, y: vr.minY))
            path.addLine(to: CGPoint(x: x2, y: vr.maxY))
            path.move(to: CGPoint(x: vr.minX, y: y1))
            path.addLine(to: CGPoint(x: vr.maxX, y: y1))
            path.move(to: CGPoint(x: vr.minX, y: y2))
            path.addLine(to: CGPoint(x: vr.maxX, y: y2))
        }
        .stroke(Color.white.opacity(0.35), lineWidth: 0.6)
        .allowsHitTesting(false)
    }

    private var cropHandle: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 18, height: 18)
            .overlay(Circle().stroke(Color.black.opacity(0.45), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
    }

    private func cornerPoint(_ corner: DevelopCropGeometry.ActiveCropCorner, viewRect vr: CGRect) -> CGPoint {
        switch corner {
        case .topLeft: CGPoint(x: vr.minX, y: vr.minY)
        case .topRight: CGPoint(x: vr.maxX, y: vr.minY)
        case .bottomLeft: CGPoint(x: vr.minX, y: vr.maxY)
        case .bottomRight: CGPoint(x: vr.maxX, y: vr.maxY)
        }
    }

    private func viewRect(for pixelCrop: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + pixelCrop.minX / iw * imageRect.width,
            y: imageRect.minY + pixelCrop.minY / ih * imageRect.height,
            width: pixelCrop.width / iw * imageRect.width,
            height: pixelCrop.height / ih * imageRect.height
        )
    }

    private func pixelPoint(from viewPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (viewPoint.x - imageRect.minX) / imageRect.width * iw,
            y: (viewPoint.y - imageRect.minY) / imageRect.height * ih
        )
    }

    private func cornerGesture(_ corner: DevelopCropGeometry.ActiveCropCorner) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if resizeStartRect == nil {
                    resizeStartRect = transientPixelCrop ?? committedPixelCrop
                }
                guard let base = resizeStartRect else { return }
                let finger = pixelPoint(from: value.location)
                let next = DevelopCropGeometry.resizeByCorner(
                    corner,
                    current: base,
                    finger: finger,
                    aspectWidthOverHeight: lockedAspect,
                    imageWidth: iw,
                    imageHeight: ih
                )
                transientPixelCrop = next
            }
            .onEnded { _ in
                commitTransientCrop()
                resizeStartRect = nil
            }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if panStartRect == nil {
                    panStartRect = transientPixelCrop ?? committedPixelCrop
                }
                guard let start = panStartRect else { return }
                let ddx = value.translation.width / imageRect.width * iw
                let ddy = value.translation.height / imageRect.height * ih
                transientPixelCrop = DevelopCropGeometry.translateCrop(start, delta: ddx, dy: ddy, imageWidth: iw, imageHeight: ih)
            }
            .onEnded { _ in
                commitTransientCrop()
                panStartRect = nil
            }
    }

    private func commitTransientCrop() {
        guard let rect = transientPixelCrop else { return }
        var s = photo.developSettings
        DevelopCropGeometry.applyPixelCrop(rect, imageWidth: iw, imageHeight: ih, to: &s)
        photo.applyDevelopSettings(s)
        try? modelContext.save()
        transientPixelCrop = nil
    }
}
