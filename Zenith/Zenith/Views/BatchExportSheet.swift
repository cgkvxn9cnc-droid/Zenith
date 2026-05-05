//
//  BatchExportSheet.swift
//  Zenith
//

import AppKit
import SwiftUI

struct BatchExportSheet: View {
    let photos: [PhotoRecord]

    @Environment(\.dismiss) private var dismiss

    @State private var format: BatchExportFormat = .jpeg
    @State private var quality: Double = 0.92
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "batch.export.title"))
                .font(.title2.bold())

            Text(String(localized: "batch.export.subtitle"))
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(String(format: String(localized: "batch.export.count_format"), photos.count))
                .font(.subheadline)

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
                    runExport()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(photos.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 440)
        .background(ZenithTheme.pageBackground)
        .alert(String(localized: "batch.export.error.title"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func runExport() {
        guard !photos.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "batch.export.choose_folder.prompt")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try BatchExporter.export(
                photos: photos,
                to: url,
                format: format,
                quality: CGFloat(quality)
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
