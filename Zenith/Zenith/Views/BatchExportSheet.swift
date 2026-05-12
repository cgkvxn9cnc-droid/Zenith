//
//  BatchExportSheet.swift
//  Zenith
//

import AppKit
import SwiftUI

struct BatchExportSheet: View {
    let photos: [PhotoRecord]
    /// Démarre l'export à l'extérieur de la feuille pour que la progression soit visible dans la barre du haut.
    var onStart: (([PhotoRecord], URL, BatchExportFormat, CGFloat) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var format: BatchExportFormat = .jpeg
    @State private var quality: Double = 0.92

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "batch.export.title"))
                .font(.title2.bold())

            Text(String(localized: "batch.export.subtitle"))
                .font(.callout)
                .foregroundStyle(.secondary)

            countSummary

            Picker(String(localized: "batch.export.format"), selection: $format) {
                ForEach(BatchExportFormat.allCases) { f in
                    Text(f.rawValue.uppercased()).tag(f)
                }
            }
            .pickerStyle(.segmented)

            if format == .jpeg {
                VStack(alignment: .leading) {
                    Text(String(localized: "batch.export.quality"))
                        .font(.caption)
                    Slider(value: $quality, in: 0.5 ... 1.0)
                    Text(String(format: "%.0f%%", quality * 100))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Text(String(localized: "batch.export.psd_note"))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button(String(localized: "common.cancel")) {
                    dismiss()
                }
                Button(String(localized: "batch.export.choose_folder")) {
                    pickDestinationAndStart()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(photos.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 440)
        .background(ZenithTheme.pageBackground)
    }

    @ViewBuilder
    private var countSummary: some View {
        if photos.isEmpty {
            Label(String(localized: "batch.export.no_selection"), systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "photo.stack")
                    .foregroundStyle(.secondary)
                Text(String(format: String(localized: "batch.export.count_format"), photos.count))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
        }
    }

    private func pickDestinationAndStart() {
        guard !photos.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "batch.export.choose_folder.prompt")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        onStart?(photos, url, format, CGFloat(quality))
        dismiss()
    }
}
