//
//  PhotoHistogramView.swift
//  Zenith
//

import SwiftUI

struct PhotoHistogramView: View {
    let photo: PhotoRecord?

    @State private var bins: [Float] = []

    private var histogramRefreshToken: String {
        guard let p = photo else { return "none" }
        let data = p.developBlob
        var hasher = Hasher()
        hasher.combine(data)
        let blobTag = "\(data.count)-\(hasher.finalize())"
        return "\(p.id.uuidString)-\(blobTag)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("workspace.histogram.title")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                Canvas { context, size in
                    guard bins.count == 256 else { return }
                    let barW = size.width / 256
                    for i in 0 ..< 256 {
                        let h = CGFloat(bins[i]) * size.height * 0.96
                        let rect = CGRect(
                            x: CGFloat(i) * barW,
                            y: size.height - h - size.height * 0.02,
                            width: max(0.5, barW),
                            height: h
                        )
                        context.fill(Path(rect), with: .color(.white.opacity(0.88)))
                    }
                }
            }
            .frame(height: 72)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .task(id: histogramRefreshToken) {
            await computeHistogram()
        }
    }

    private func computeHistogram() async {
        guard let photo else {
            bins = []
            return
        }
        let url: URL
        do {
            url = try photo.resolvedURL()
        } catch {
            bins = []
            return
        }
        let settings = photo.developSettings
        let ci = await Task.detached(priority: .userInitiated) {
            let started = url.startAccessingSecurityScopedResource()
            defer {
                if started { url.stopAccessingSecurityScopedResource() }
            }
            return DevelopPreviewRenderer.developedCIImage(url: url, settings: settings)
        }.value
        guard let ci else {
            bins = []
            return
        }
        let next = await Task.detached(priority: .utility) {
            ImageHistogram.luminanceBins(from: ci)
        }.value
        bins = next
    }
}
