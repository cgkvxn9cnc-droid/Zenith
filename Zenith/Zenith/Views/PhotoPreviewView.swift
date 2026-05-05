//
//  PhotoPreviewView.swift
//  Zenith
//

import AppKit
import SwiftUI

struct PhotoPreviewView: View {
    let photo: PhotoRecord?
    /// Affiche le fichier brut (réglages ignorés) pour comparaison « avant ».
    var compareOriginal: Bool = false
    /// 1,0 = taille « adaptée à la zone » ; minimum 5 % (0,05), maximum ~1600 %.
    @Binding var zoomScale: CGFloat
    @Binding var developCanvasTool: DevelopCanvasTool
    var onHealTapNormalized: ((CGFloat, CGFloat) -> Void)?

    @State private var preview: NSImage?
    @State private var loadToken = UUID()
    @State private var panOffset: CGSize = .zero

    private let minZoom: CGFloat = 0.05
    private let maxZoom: CGFloat = 16

    init(
        photo: PhotoRecord?,
        compareOriginal: Bool = false,
        zoomScale: Binding<CGFloat> = .constant(1.0),
        developCanvasTool: Binding<DevelopCanvasTool> = .constant(.none),
        onHealTapNormalized: ((CGFloat, CGFloat) -> Void)? = nil
    ) {
        self.photo = photo
        self.compareOriginal = compareOriginal
        _zoomScale = zoomScale
        _developCanvasTool = developCanvasTool
        self.onHealTapNormalized = onHealTapNormalized
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ZenithTheme.canvasBackground

                if let preview {
                    let imgSize = CGSize(width: preview.size.width, height: preview.size.height)
                    let fitted = Self.aspectFitSize(imageSize: imgSize, in: geo.size)
                    let zoomedW = max(1, fitted.width * zoomScale)
                    let zoomedH = max(1, fitted.height * zoomScale)

                    Image(nsImage: preview)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: zoomedW, height: zoomedH)
                        .offset(panOffset)
                        .shadow(radius: 20)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("preview.empty")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay {
                if photo != nil, developCanvasTool != .heal {
                    PhotoPreviewTrackpadHost(
                        zoomScale: $zoomScale,
                        panOffset: $panOffset,
                        minZoom: minZoom,
                        maxZoom: maxZoom
                    )
                }
            }
            .overlay {
                Group {
                    if let prev = preview, let item = photo, developCanvasTool != .none {
                        toolOverlayLayer(viewSize: geo.size, previewImage: prev, photo: item)
                    }
                }
            }
        }
        .clipped()
        .onAppear { scheduleLoad() }
        .onChange(of: photo?.id) { _, _ in
            panOffset = .zero
            zoomScale = 1
            scheduleLoad()
        }
        .onChange(of: photo?.developBlob) { _, _ in scheduleLoad() }
        .onChange(of: compareOriginal) { _, _ in scheduleLoad() }
        .onChange(of: zoomScale) { _, newValue in
            let clamped = clampZoom(newValue)
            if clamped != newValue {
                zoomScale = clamped
            }
            if abs(clamped - 1.0) < 0.02 {
                panOffset = .zero
            }
        }
    }

    @ViewBuilder
    private func toolOverlayLayer(viewSize: CGSize, previewImage: NSImage, photo: PhotoRecord) -> some View {
        let frame = imageDisplayRect(viewSize: viewSize, preview: previewImage)
        let pixelRef = Self.referencePixelSize(photo: photo, preview: previewImage)
        switch developCanvasTool {
        case .crop:
            DevelopCropInteractionOverlay(
                photo: photo,
                viewportSize: viewSize,
                imageRect: frame,
                imagePixelSize: pixelRef
            )
        case .heal:
            DevelopPreviewToolOverlay(
                viewportSize: viewSize,
                imageRect: frame,
                onHealAtNormalized: { nx, ny in
                    onHealTapNormalized?(nx, ny)
                }
            )
        default:
            EmptyView()
        }
    }

    private static func referencePixelSize(photo: PhotoRecord, preview: NSImage) -> CGSize {
        let w = photo.pixelWidth > 0 ? CGFloat(photo.pixelWidth) : preview.size.width
        let h = photo.pixelHeight > 0 ? CGFloat(photo.pixelHeight) : preview.size.height
        return CGSize(width: max(1, w), height: max(1, h))
    }

    private func imageDisplayRect(viewSize: CGSize, preview: NSImage) -> CGRect {
        let imgSize = CGSize(width: preview.size.width, height: preview.size.height)
        let fitted = Self.aspectFitSize(imageSize: imgSize, in: viewSize)
        let zw = max(1, fitted.width * zoomScale)
        let zh = max(1, fitted.height * zoomScale)
        let x = (viewSize.width - zw) / 2 + panOffset.width
        let y = (viewSize.height - zh) / 2 + panOffset.height
        return CGRect(x: x, y: y, width: zw, height: zh)
    }

    private func clampZoom(_ z: CGFloat) -> CGFloat {
        min(max(z, minZoom), maxZoom)
    }

    private static func aspectFitSize(imageSize: CGSize, in bounds: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return .zero
        }
        let s = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        return CGSize(width: imageSize.width * s, height: imageSize.height * s)
    }

    private func scheduleLoad() {
        loadToken = UUID()
        let token = loadToken
        Task { await loadIfCurrent(token) }
    }

    @MainActor
    private func loadIfCurrent(_ token: UUID) async {
        guard token == loadToken else { return }
        guard let photo else {
            preview = nil
            return
        }
        do {
            let url = try photo.resolvedURL()
            let started = url.startAccessingSecurityScopedResource()
            defer { if started { url.stopAccessingSecurityScopedResource() } }
            guard token == loadToken else { return }
            if compareOriginal {
                preview = NSImage(contentsOf: url)
                return
            }
            let img = DevelopPreviewRenderer.render(url: url, settings: photo.developSettings)
            guard token == loadToken else { return }
            preview = img ?? NSImage(contentsOf: url)
        } catch {
            preview = nil
        }
    }
}
