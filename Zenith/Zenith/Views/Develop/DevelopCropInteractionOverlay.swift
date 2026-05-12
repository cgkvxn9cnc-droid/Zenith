//
//  DevelopCropInteractionOverlay.swift
//  Zenith
//

import AppKit
import SwiftData
import SwiftUI

/// Recadrage : assombrissement extérieur, grille, **8 poignées** (coins + milieux), conversion SwiftUI ↔ Core Image (bas‑gauche).
struct DevelopCropInteractionOverlay: View {
    private let cropCoordinateSpaceName = "ZenithDevelopCropViewport"

    @Bindable var photo: PhotoRecord
    let viewportSize: CGSize
    let imageRect: CGRect
    /// Taille fichier source (`pixelWidth` × `pixelHeight`) — la toile logique du crop inclut la rotation via `rotatedCanvasPixelSize`.
    let imagePixelSize: CGSize

    @Binding var zoomScale: CGFloat
    @Binding var panOffset: CGSize
    var zoomMin: CGFloat = 0.05
    var zoomMax: CGFloat = 16

    @Environment(\.modelContext) private var modelContext

    @State private var transientPixelCrop: CGRect?
    @State private var resizeStartRect: CGRect?
    @State private var panGestureBaseCrop: CGRect?

    private var iw: CGFloat { max(1, imagePixelSize.width) }
    private var ih: CGFloat { max(1, imagePixelSize.height) }

    private var canvas: CGSize {
        DevelopCropGeometry.rotatedCanvasPixelSize(
            imageWidth: iw,
            imageHeight: ih,
            angleDegrees: photo.developSettings.straightenAngle
        )
    }

    private var cw: CGFloat { canvas.width }
    private var ch: CGFloat { canvas.height }

    private var committedPixelCrop: CGRect {
        DevelopCropGeometry.pixelCropRectCanvasBL(from: photo.developSettings, imageWidth: iw, imageHeight: ih)
    }

    private var livePixelCrop: CGRect {
        transientPixelCrop ?? committedPixelCrop
    }

    private var lockedAspect: CGFloat? {
        let preset = DevelopCropAspectPreset(rawValue: photo.developSettings.cropAspectPresetRaw) ?? .free
        return preset.widthOverHeight(imageNaturalRatio: Double(iw / ih))
    }

    private enum CropDragHandle: Hashable {
        case corner(DevelopCropGeometry.ActiveCropCorner)
        case edge(DevelopCropGeometry.ActiveCropEdge)

        fileprivate var cursor: NSCursor {
            switch self {
            case .corner:
                return .crosshair
            case .edge(.left), .edge(.right):
                return .resizeLeftRight
            case .edge(.top), .edge(.bottom):
                return .resizeUpDown
            }
        }
    }

    var body: some View {
        ZStack {
            PhotoPreviewTrackpadHost(
                zoomScale: $zoomScale,
                panOffset: $panOffset,
                viewportSize: viewportSize,
                minZoom: zoomMin,
                maxZoom: zoomMax,
                allowsMouseDragPan: false
            )

            cropOutsideDim

            let vr = viewRect(forCropCanvasBL: livePixelCrop)
            Path { p in
                p.addRect(vr)
            }
            .stroke(Color.white.opacity(0.95), lineWidth: 1.2)
            .allowsHitTesting(false)

            cropRuleOfThirds(in: vr)

            if abs(photo.developSettings.straightenAngle) > 0.05 {
                straightenGrid(in: vr)
            }

            Color.clear
                .frame(width: vr.width, height: vr.height)
                .position(x: vr.midX, y: vr.midY)
                .contentShape(Rectangle())
                .gesture(panGesture)

            ForEach(
                [
                    CropDragHandle.corner(.topLeft),
                    CropDragHandle.corner(.topRight),
                    CropDragHandle.corner(.bottomLeft),
                    CropDragHandle.corner(.bottomRight)
                ],
                id: \.self
            ) { handle in
                cropCornerHandle
                    .position(handlePosition(handle, viewRect: vr))
                    .highPriorityGesture(cornerOrEdgeGesture(handle))
                    .modifier(CursorHoverModifier(cursor: handle.cursor))
            }

            ForEach(
                [
                    CropDragHandle.edge(.top),
                    CropDragHandle.edge(.bottom),
                    CropDragHandle.edge(.left),
                    CropDragHandle.edge(.right)
                ],
                id: \.self
            ) { handle in
                cropEdgeHandle
                    .position(handlePosition(handle, viewRect: vr))
                    .highPriorityGesture(cornerOrEdgeGesture(handle))
                    .modifier(CursorHoverModifier(cursor: handle.cursor))
            }
        }
        .coordinateSpace(name: cropCoordinateSpaceName)
        .frame(width: viewportSize.width, height: viewportSize.height)
        .onChange(of: photo.developBlob) { _, _ in
            transientPixelCrop = nil
            resizeStartRect = nil
            panGestureBaseCrop = nil
        }
    }

    private struct CursorHoverModifier: ViewModifier {
        let cursor: NSCursor

        func body(content: Content) -> some View {
            content.onHover { inside in
                if inside {
                    cursor.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
    }

    private var cropOutsideDim: some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: viewportSize))
            path.addRect(viewRect(forCropCanvasBL: livePixelCrop))
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

    private func straightenGrid(in vr: CGRect) -> some View {
        let lineCount = 8
        return Path { path in
            for i in 1..<lineCount {
                let frac = CGFloat(i) / CGFloat(lineCount)
                let x = vr.minX + vr.width * frac
                path.move(to: CGPoint(x: x, y: vr.minY))
                path.addLine(to: CGPoint(x: x, y: vr.maxY))
                let y = vr.minY + vr.height * frac
                path.move(to: CGPoint(x: vr.minX, y: y))
                path.addLine(to: CGPoint(x: vr.maxX, y: y))
            }
        }
        .stroke(Color.yellow.opacity(0.25), lineWidth: 0.5)
        .allowsHitTesting(false)
    }

    private var cropCornerHandle: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 18, height: 18)
            .overlay(Circle().stroke(Color.black.opacity(0.45), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
    }

    private var cropEdgeHandle: some View {
        Capsule()
            .fill(Color.white)
            .frame(width: 22, height: 10)
            .overlay(Capsule().stroke(Color.black.opacity(0.45), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
    }

    private func handlePosition(_ handle: CropDragHandle, viewRect vr: CGRect) -> CGPoint {
        switch handle {
        case .corner(let c):
            switch c {
            case .topLeft: CGPoint(x: vr.minX, y: vr.minY)
            case .topRight: CGPoint(x: vr.maxX, y: vr.minY)
            case .bottomLeft: CGPoint(x: vr.minX, y: vr.maxY)
            case .bottomRight: CGPoint(x: vr.maxX, y: vr.maxY)
            }
        case .edge(let e):
            switch e {
            case .top: CGPoint(x: vr.midX, y: vr.minY)
            case .bottom: CGPoint(x: vr.midX, y: vr.maxY)
            case .left: CGPoint(x: vr.minX, y: vr.midY)
            case .right: CGPoint(x: vr.maxX, y: vr.midY)
            }
        }
    }

    /// Conversion rectangle toile bas‑gauche → SwiftUI (haut‑gauche).
    private func viewRect(forCropCanvasBL cropBL: CGRect) -> CGRect {
        guard cw > 0, ch > 0 else { return .zero }
        let topY = ch - cropBL.maxY
        let fracX = cropBL.minX / cw
        let fracTop = topY / ch
        let fracW = cropBL.width / cw
        let fracH = cropBL.height / ch
        return CGRect(
            x: imageRect.minX + fracX * imageRect.width,
            y: imageRect.minY + fracTop * imageRect.height,
            width: fracW * imageRect.width,
            height: fracH * imageRect.height
        )
    }

    /// Pointeur SwiftUI → coordonnées toile bas‑gauche.
    private func pixelPointCanvasBL(from viewPoint: CGPoint) -> CGPoint {
        let fracX = (viewPoint.x - imageRect.minX) / imageRect.width
        let fracYTop = (viewPoint.y - imageRect.minY) / imageRect.height
        let xBL = fracX * cw
        let yFromTop = fracYTop * ch
        let yBL = ch - yFromTop
        return CGPoint(x: xBL, y: yBL)
    }

    private func cornerOrEdgeGesture(_ handle: CropDragHandle) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(cropCoordinateSpaceName))
            .onChanged { value in
                if resizeStartRect == nil {
                    resizeStartRect = transientPixelCrop ?? committedPixelCrop
                }
                guard let base = resizeStartRect else { return }
                let finger = pixelPointCanvasBL(from: value.location)
                let next: CGRect = {
                    switch handle {
                    case .corner(let c):
                        return DevelopCropGeometry.resizeByCorner(
                            c,
                            current: base,
                            finger: finger,
                            aspectWidthOverHeight: lockedAspect,
                            canvasWidth: cw,
                            canvasHeight: ch
                        )
                    case .edge(let e):
                        return DevelopCropGeometry.resizeByEdge(
                            e,
                            current: base,
                            finger: finger,
                            aspectWidthOverHeight: lockedAspect,
                            canvasWidth: cw,
                            canvasHeight: ch
                        )
                    }
                }()
                transientPixelCrop = next
            }
            .onEnded { _ in
                commitTransientCrop()
                resizeStartRect = nil
            }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(cropCoordinateSpaceName))
            .onChanged { value in
                if panGestureBaseCrop == nil {
                    panGestureBaseCrop = transientPixelCrop ?? committedPixelCrop
                }
                guard let start = panGestureBaseCrop else { return }
                let dxBL = value.translation.width / imageRect.width * cw
                let dyBL = -value.translation.height / imageRect.height * ch
                transientPixelCrop = DevelopCropGeometry.translateCrop(start, delta: dxBL, dy: dyBL, canvasWidth: cw, canvasHeight: ch)
            }
            .onEnded { _ in
                commitTransientCrop()
                panGestureBaseCrop = nil
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
