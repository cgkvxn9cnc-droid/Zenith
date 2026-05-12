//
//  DevelopWorkspaceChrome.swift
//  Zenith
//

import AppKit
import CoreImage
import SwiftData
import SwiftUI

/// Miniature de navigation (repère visuel sur la photo courante), style Lightroom.
struct DevelopNavigatorThumb: View {
    let photo: PhotoRecord

    @State private var thumb: NSImage?
    private let side: CGFloat = 76

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("develop.navigator.title")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Group {
                if let thumb {
                    Image(nsImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: photo.id) {
            await loadThumb()
        }
    }

    private func loadThumb() async {
        do {
            let url = try photo.resolvedURL()
            let target = side * 2
            /// Le décodage RAW peut prendre plusieurs centaines de ms ; on le sort impérativement du
            /// MainActor pour éviter de bloquer le commit de la fenêtre au tout premier rendu (au
            /// démarrage, plusieurs cellules de la pellicule + ce thumb peuvent être instanciés
            /// simultanément). Le throttle global protège `RawCamera-Provider-Render-Queue` des
            /// accès concurrents qui mènent à un deadlock.
            let detached = Task.detached(priority: .userInitiated) { () -> ThumbnailDecodeResult in
                if Task.isCancelled { return ThumbnailDecodeResult(nil) }
                do {
                    try await ThumbnailDecodeThrottle.shared.acquire()
                } catch {
                    return ThumbnailDecodeResult(nil)
                }
                if Task.isCancelled {
                    await ThumbnailDecodeThrottle.shared.release()
                    return ThumbnailDecodeResult(nil)
                }
                let started = url.startAccessingSecurityScopedResource()
                let img = ThumbnailLoader.thumbnail(for: url, maxPixel: target)
                if started { url.stopAccessingSecurityScopedResource() }
                await ThumbnailDecodeThrottle.shared.release()
                return ThumbnailDecodeResult(img)
            }
            let result: ThumbnailDecodeResult = await withTaskCancellationHandler {
                await detached.value
            } onCancel: {
                detached.cancel()
            }
            if Task.isCancelled { return }
            self.thumb = result.image
        } catch {
            self.thumb = nil
        }
    }
}

/// Barre d’outils sous l’histogramme : recadrage, retouche locale, suppression de couleur ciblée.
struct DevelopToolStrip: View {
    @Bindable var photo: PhotoRecord
    @Binding var activeTool: DevelopCanvasTool
    @Environment(\.modelContext) private var modelContext

    @State private var commandKeyHeld = false
    @State private var horizonBusy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 2) {
                toolToggle(.crop, systemName: "crop", help: "develop.tool.crop")
                toolToggle(.heal, systemName: "bandage", help: "develop.tool.heal")
                toolToggle(.smartRemove, systemName: "wand.and.stars", help: "develop.tool.smart_remove")
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)

            if activeTool == .crop {
                cropControls
            }

            if activeTool == .heal {
                Button("develop.heal.clear_spot") {
                    var s = photo.developSettings
                    s.healNormX = -1
                    s.healNormY = -1
                    s.healRadiusPx = 0
                    photo.applyDevelopSettings(s)
                    try? modelContext.save()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ZenithTheme.developCardFill.opacity(0.85))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(alignment: .topLeading) {
            CommandKeyHeldMonitor(isHeld: $commandKeyHeld)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
        }
    }

    private var cropControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("develop.crop.aspect_picker", selection: aspectPresetBinding) {
                ForEach(DevelopCropAspectPreset.allCases) { preset in
                    Text(preset.labelKey).tag(preset)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)

            straightenSlider

            cropFlipRow

            Text("develop.crop.drag_hint")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("develop.crop.cmd_reset_hint")
                .font(.caption2)
                .foregroundStyle(.tertiary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            if commandKeyHeld {
                Button(String(localized: "develop.crop.reset")) {
                    resetCropFramingOnly()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var cropFlipRow: some View {
        HStack(spacing: 8) {
            Toggle(isOn: flipHorizontalBinding) {
                Image(systemName: "arrow.left.and.right")
            }
            .toggleStyle(.button)
            .help(Text("develop.crop.flip_horizontal"))

            Toggle(isOn: flipVerticalBinding) {
                Image(systemName: "arrow.up.and.down")
            }
            .toggleStyle(.button)
            .help(Text("develop.crop.flip_vertical"))

            Button {
                Task { await runAutoHorizon() }
            } label: {
                Image(systemName: "level")
            }
            .buttonStyle(.bordered)
            .disabled(horizonBusy || photo.pixelWidth < 4)
            .help(Text("develop.crop.auto_horizon"))
        }
        .controlSize(.small)
    }

    private var flipHorizontalBinding: Binding<Bool> {
        Binding(
            get: { photo.developSettings.cropFlipHorizontal },
            set: { newValue in
                var s = photo.developSettings
                s.cropFlipHorizontal = newValue
                photo.applyDevelopSettings(s)
                try? modelContext.save()
            }
        )
    }

    private var flipVerticalBinding: Binding<Bool> {
        Binding(
            get: { photo.developSettings.cropFlipVertical },
            set: { newValue in
                var s = photo.developSettings
                s.cropFlipVertical = newValue
                photo.applyDevelopSettings(s)
                try? modelContext.save()
            }
        )
    }

    private func runAutoHorizon() async {
        guard !horizonBusy else { return }
        horizonBusy = true
        defer { horizonBusy = false }
        guard let url = try? photo.resolvedURL() else { return }
        let began = url.startAccessingSecurityScopedResource()
        defer { if began { url.stopAccessingSecurityScopedResource() } }
        guard let ci = ZenithImageSourceLoader.ciImage(
            contentsOf: url,
            maxPixelDimension: 2048,
            draftMode: true
        ) else { return }
        guard let deg = await HorizonStraightenService.estimateStraightenDegrees(ciImage: ci) else { return }
        var s = photo.developSettings
        s.straightenAngle = deg
        photo.applyDevelopSettings(s)
        try? modelContext.save()
    }

    private var straightenSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("develop.crop.straighten")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f°", photo.developSettings.straightenAngle))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Slider(value: straightenAngleBinding, in: -45...45, step: 0.1) {
                EmptyView()
            }
            .controlSize(.small)
        }
    }

    private var straightenAngleBinding: Binding<Double> {
        Binding(
            get: { photo.developSettings.straightenAngle },
            set: { newValue in
                var s = photo.developSettings
                s.straightenAngle = newValue
                photo.applyDevelopSettings(s)
                try? modelContext.save()
            }
        )
    }

    private func resetCropFramingOnly() {
        var s = photo.developSettings
        s.resetCropToFullFrame()
        photo.applyDevelopSettings(s)
        try? modelContext.save()
    }

    private var aspectPresetBinding: Binding<DevelopCropAspectPreset> {
        Binding(
            get: { DevelopCropAspectPreset(rawValue: photo.developSettings.cropAspectPresetRaw) ?? .free },
            set: { newPreset in
                var s = photo.developSettings
                s.cropAspectPresetRaw = newPreset.rawValue
                let iw = CGFloat(max(photo.pixelWidth, 1))
                let ih = CGFloat(max(photo.pixelHeight, 1))
                let natural = iw / ih
                let ratio = newPreset.widthOverHeight(imageNaturalRatio: natural)
                if newPreset != .free {
                    let canvas = DevelopCropGeometry.rotatedCanvasPixelSize(
                        imageWidth: iw,
                        imageHeight: ih,
                        angleDegrees: s.straightenAngle
                    )
                    let r = DevelopCropGeometry.maxCenteredRect(
                        imageWidth: canvas.width,
                        imageHeight: canvas.height,
                        widthOverHeight: ratio
                    )
                    DevelopCropGeometry.applyPixelCrop(r, imageWidth: iw, imageHeight: ih, to: &s)
                }
                photo.applyDevelopSettings(s)
                try? modelContext.save()
            }
        )
    }

    private func toolToggle(_ tool: DevelopCanvasTool, systemName: String, help: LocalizedStringKey) -> some View {
        let selected = activeTool == tool
        return Button {
            if tool == .smartRemove {
                activateSmartRemove()
                return
            }
            activeTool = selected ? .none : tool
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .frame(width: 34, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? Color.white.opacity(0.12) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(help))
    }

    private func activateSmartRemove() {
        activeTool = .none
        NotificationCenter.default.post(name: .zenithScrollDevelopGrainNoise, object: nil)
    }
}
