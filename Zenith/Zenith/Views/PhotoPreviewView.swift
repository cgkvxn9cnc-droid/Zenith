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

    @State private var preview: NSImage?
    @State private var loadToken = UUID()
    @State private var panOffset: CGSize = .zero
    @State private var panBase: CGSize = .zero
    @State private var isDraggingPan = false
    @State private var pinchBaseZoom: CGFloat = 1.0
    @State private var isPinching = false

    private let minZoom: CGFloat = 0.05
    private let maxZoom: CGFloat = 16

    init(
        photo: PhotoRecord?,
        compareOriginal: Bool = false,
        zoomScale: Binding<CGFloat> = .constant(1.0)
    ) {
        self.photo = photo
        self.compareOriginal = compareOriginal
        _zoomScale = zoomScale
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
                    let canPan = abs(zoomScale - 1) > 0.001
                        || abs(panOffset.width) > 0.5
                        || abs(panOffset.height) > 0.5

                    Image(nsImage: preview)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: zoomedW, height: zoomedH)
                        .offset(panOffset)
                        .shadow(radius: 20)
                        .simultaneousGesture(trackpadMagnification)
                        .simultaneousGesture(panGesture(allowed: canPan))
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
            // Ne pas confondre « zoom 100 % » (taille adaptée) et un fort dézoom (ex. 5 %).
            if abs(clamped - 1.0) < 0.02 {
                panOffset = .zero
            }
        }
    }

    private var trackpadMagnification: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if !isPinching {
                    isPinching = true
                    pinchBaseZoom = zoomScale
                }
                zoomScale = clampZoom(pinchBaseZoom * value)
            }
            .onEnded { _ in
                isPinching = false
                pinchBaseZoom = zoomScale
            }
    }

    private func panGesture(allowed: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard allowed else { return }
                if !isDraggingPan {
                    isDraggingPan = true
                    panBase = panOffset
                }
                panOffset = CGSize(
                    width: panBase.width + value.translation.width,
                    height: panBase.height + value.translation.height
                )
            }
            .onEnded { _ in
                isDraggingPan = false
            }
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
