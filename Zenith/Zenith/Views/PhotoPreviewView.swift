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
    @State private var originalPreview: NSImage?
    @State private var loadToken = UUID()
    @State private var panOffset: CGSize = .zero
    @State private var previewDebounceTask: Task<Void, Never>?
    @State private var colorProfileCaption: String?

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

                if compareOriginal, let orig = originalPreview, let dev = preview {
                    DevelopBeforeAfterOverlay(
                        originalImage: orig,
                        developedImage: dev
                    )
                } else if let preview {
                    let imgSize = CGSize(width: preview.size.width, height: preview.size.height)
                    let fitted = Self.aspectFitSize(imageSize: imgSize, in: geo.size)
                    let zoomedW = max(1, fitted.width * zoomScale)
                    let zoomedH = max(1, fitted.height * zoomScale)

                    Group {
                        Image(nsImage: preview)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: zoomedW, height: zoomedH)
                            .offset(panOffset)
                    }
                    .compositingGroup()
                    .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 6)
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

                if let caption = colorProfileCaption, photo != nil {
                    VStack {
                        Spacer()
                        Text(caption)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                    .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay {
                if photo != nil, !compareOriginal, developCanvasTool != .heal && developCanvasTool != .crop {
                    PhotoPreviewTrackpadHost(
                        zoomScale: $zoomScale,
                        panOffset: $panOffset,
                        viewportSize: geo.size,
                        minZoom: minZoom,
                        maxZoom: maxZoom
                    )
                }
            }
            .overlay {
                Group {
                    if let prev = preview, let item = photo, !compareOriginal, developCanvasTool != .none {
                        toolOverlayLayer(viewSize: geo.size, previewImage: prev, photo: item)
                    }
                }
            }
        }
        .clipped()
        .onAppear { scheduleLoad(immediate: true) }
        .onChange(of: photo?.id) { _, _ in
            panOffset = .zero
            zoomScale = 1
            colorProfileCaption = nil
            DevelopPreviewCache.shared.invalidate()
            scheduleLoad(immediate: true)
        }
        .onChange(of: photo?.developBlob) { _, _ in
            DevelopPreviewCache.shared.invalidateResult()
            scheduleLoad(immediate: false)
        }
        .onChange(of: compareOriginal) { _, _ in scheduleLoad(immediate: true) }
        .onChange(of: developCanvasTool) { _, _ in scheduleLoad(immediate: true) }
        .onChange(of: zoomScale) { _, newValue in
            let clamped = clampZoom(newValue)
            if clamped != newValue {
                zoomScale = clamped
            }
            if abs(clamped - 1.0) < 0.02 {
                panOffset = .zero
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .zenithCenterPreview)) { _ in
            withAnimation(.snappy(duration: 0.2)) {
                panOffset = .zero
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .zenithColorPreferencesDidChange)) { _ in
            if let photo, let url = try? photo.resolvedURL() {
                updateColorProfileCaption(url: url)
            }
            scheduleLoad(immediate: true)
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
                imagePixelSize: pixelRef,
                zoomScale: $zoomScale,
                panOffset: $panOffset,
                zoomMin: minZoom,
                zoomMax: maxZoom
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

    /// `immediate: false` utilise un proxy basse-res pendant le drag, puis déclenche le rendu full-res après debounce.
    private func scheduleLoad(immediate: Bool) {
        previewDebounceTask?.cancel()
        if immediate {
            previewDebounceTask = nil
            loadToken = UUID()
            let token = loadToken
            Task { await loadIfCurrent(token, proxyOnly: false) }
            return
        }
        // Proxy immédiat pour fluidité, puis full-res après debounce
        loadToken = UUID()
        let proxyToken = loadToken
        Task { await loadIfCurrent(proxyToken, proxyOnly: true) }
        previewDebounceTask = Task {
            /// ~14 images/s plein rés après la fin du drag : moins de relances concurrentes sur RAW lourds.
            try? await Task.sleep(for: .milliseconds(72))
            guard !Task.isCancelled else { return }
            await flushPreviewAfterDebounce()
        }
    }

    @MainActor
    private func flushPreviewAfterDebounce() async {
        loadToken = UUID()
        await loadIfCurrent(loadToken, proxyOnly: false)
    }

    @MainActor
    private func loadIfCurrent(_ token: UUID, proxyOnly: Bool) async {
        guard token == loadToken else { return }
        guard let photo else {
            preview = nil
            colorProfileCaption = nil
            return
        }
        do {
            let url = try photo.resolvedURL()
            let settings = photo.developSettings
            guard token == loadToken else { return }
            if compareOriginal {
                let capturedToken = token
                let both = await Task.detached(priority: .userInitiated) {
                    let began = url.startAccessingSecurityScopedResource()
                    defer { if began { url.stopAccessingSecurityScopedResource() } }
                    var orig = NSImage(contentsOf: url)
                    if orig == nil {
                        let neutralReq = DevelopPreviewCache.RenderRequest(
                            url: url, settings: DevelopSettings.neutral, applyCrop: true, proxyOnly: false
                        )
                        orig = await DevelopPreviewCache.shared.render(neutralReq).image
                    }
                    let request = DevelopPreviewCache.RenderRequest(
                        url: url, settings: settings, applyCrop: true, proxyOnly: false
                    )
                    let dev = await DevelopPreviewCache.shared.render(request).image
                    return (orig, dev)
                }.value
                guard capturedToken == loadToken else { return }
                originalPreview = both.0
                preview = both.1 ?? both.0
                updateColorProfileCaption(url: url)
                return
            }
            originalPreview = nil
            let skipCropPreview = developCanvasTool == .crop
            let request = DevelopPreviewCache.RenderRequest(
                url: url,
                settings: settings,
                applyCrop: !skipCropPreview,
                proxyOnly: proxyOnly
            )
            let result = await Task.detached(priority: proxyOnly ? .high : .userInitiated) {
                let began = url.startAccessingSecurityScopedResource()
                defer { if began { url.stopAccessingSecurityScopedResource() } }
                return await DevelopPreviewCache.shared.render(request)
            }.value
            guard token == loadToken else { return }
            if let img = result.image {
                preview = img
            } else if !proxyOnly {
                let began = url.startAccessingSecurityScopedResource()
                defer { if began { url.stopAccessingSecurityScopedResource() } }
                preview = NSImage(contentsOf: url)
            }
            updateColorProfileCaption(url: url)
        } catch {
            preview = nil
            colorProfileCaption = nil
        }
    }

    private func updateColorProfileCaption(url: URL) {
        let assumed = ZenithAssumedRGBProfile.current
        if let desc = ColorProfileReader.describeIfBitmap(url: url) {
            var s = desc.statusLabel(assumed: assumed)
            if ZenithColorPreferences.cmykSoftProofEnabled, desc.isCMYK {
                s += " — " + String(localized: "color.cmyk.softproof.hint")
            }
            colorProfileCaption = s
        } else {
            colorProfileCaption = String(localized: "color.profile.status.raw")
        }
    }
}
