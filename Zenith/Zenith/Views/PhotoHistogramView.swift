//
//  PhotoHistogramView.swift
//  Zenith
//

import SwiftUI

struct PhotoHistogramView: View {
    let photo: PhotoRecord?

    @State private var data: RGBLHistogramData = .flat
    @State private var exifLine: PhotoEXIFFormatter.Line?

    private var histogramRefreshToken: String {
        guard let p = photo else { return "none" }
        let blob = p.developBlob
        var hasher = Hasher()
        hasher.combine(blob)
        let blobTag = "\(blob.count)-\(hasher.finalize())"
        return "\(p.id.uuidString)-\(blobTag)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            histogramBlock
                .padding(.bottom, 6)

            exifMetadataRow
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("workspace.histogram.title"))
        /// `histogramRefreshToken` inclut déjà `developBlob` : un `onChange` supplémentaire doublait le travail
        /// à chaque pixel de curseur et saturait le CPU.
        .task(id: histogramRefreshToken) {
            await computeHistogram()
        }
    }

    private var histogramBlock: some View {
        ZStack(alignment: .top) {
            Canvas { context, canvasSize in
                guard data.luminance.count == 256, canvasSize.width > 4, canvasSize.height > 4 else { return }
                let inset: CGFloat = 2
                let drawRect = CGRect(
                    x: inset,
                    y: inset,
                    width: canvasSize.width - inset * 2,
                    height: canvasSize.height - inset * 2
                )
                context.clip(to: Rectangle().path(in: drawRect))
                context.fill(channelPath(bins: data.luminance, rect: drawRect), with: .color(Color(white: 0.82).opacity(0.28)))
                context.fill(channelPath(bins: data.blue, rect: drawRect), with: .color(Color(red: 0.15, green: 0.45, blue: 1.0).opacity(0.38)))
                context.fill(channelPath(bins: data.green, rect: drawRect), with: .color(Color(red: 0.2, green: 0.85, blue: 0.35).opacity(0.38)))
                context.fill(channelPath(bins: data.red, rect: drawRect), with: .color(Color(red: 1.0, green: 0.22, blue: 0.18).opacity(0.38)))
            }
            .allowsHitTesting(false)

            Rectangle()
                .strokeBorder(Color.black, lineWidth: 1)
                .padding(0.5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 84)
        .background(ZenithTheme.pageBackground)
    }

    private var exifMetadataRow: some View {
        HStack(spacing: 0) {
            Text(isoColumn)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(focalColumn)
                .frame(maxWidth: .infinity, alignment: .center)
            Text(apertureColumn)
                .frame(maxWidth: .infinity, alignment: .center)
            Text(shutterColumn)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .regular, design: .default))
        .foregroundStyle(Color(white: 0.52))
    }

    private var isoColumn: String {
        guard let v = exifLine?.iso else { return "—" }
        return "ISO \(v)"
    }

    private var focalColumn: String {
        guard let v = exifLine?.focalLengthMM else { return "—" }
        return "\(v) mm"
    }

    private var apertureColumn: String {
        guard let v = exifLine?.aperture else { return "—" }
        return "f / \(v)"
    }

    private var shutterColumn: String {
        guard let v = exifLine?.shutter else { return "—" }
        return v
    }

    private func channelPath(bins: [Float], rect: CGRect) -> Path {
        var path = Path()
        guard bins.count == 256, rect.width > 0, rect.height > 0 else { return path }
        let w = rect.width
        let h = rect.height
        let step = w / 256
        let bottom = rect.maxY
        path.move(to: CGPoint(x: rect.minX, y: bottom))
        for i in 0 ..< 256 {
            let x = rect.minX + CGFloat(i) * step
            let nh = CGFloat(bins[i]) * h * 0.96
            path.addLine(to: CGPoint(x: x, y: bottom - nh))
        }
        path.addLine(to: CGPoint(x: rect.minX + w, y: bottom))
        path.closeSubpath()
        return path
    }

    private func computeHistogram() async {
        guard let photo else {
            data = .flat
            exifLine = nil
            return
        }
        let settings = photo.developSettings
        if settings != .neutral {
            /// Regroupe les rafales de curseur : le `.task(id:)` annule la tâche précédente, mais on évite quand
            /// même de lancer un pipeline complet à 60 Hz pendant le glissé.
            do {
                try await Task.sleep(for: .milliseconds(90))
            } catch {
                return
            }
        }
        let url: URL
        do {
            url = try photo.resolvedURL()
        } catch {
            data = .flat
            exifLine = nil
            return
        }
        let ciAndExif = await Task.detached(priority: .utility) {
            let started = url.startAccessingSecurityScopedResource()
            defer {
                if started { url.stopAccessingSecurityScopedResource() }
            }
            let ci = DevelopPreviewRenderer.developedCIImage(
                url: url,
                settings: settings,
                quality: .fast,
                maxSourceDecodeDimension: 640
            )
            let exif = PhotoEXIFFormatter.line(from: url)
            return (ci, exif)
        }.value
        exifLine = ciAndExif.1
        guard let ci = ciAndExif.0 else {
            data = .flat
            return
        }
        let next = await Task.detached(priority: .utility) {
            ImageHistogram.rgbLHistogram(from: ci)
        }.value
        data = next
    }
}
