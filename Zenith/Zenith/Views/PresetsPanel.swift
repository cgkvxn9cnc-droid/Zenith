//
//  PresetsPanel.swift
//  Zenith
//

import SwiftData
import SwiftUI

struct PresetsPanel: View {
    @Query(sort: \PresetRecord.createdAt, order: .reverse) private var presets: [PresetRecord]
    @Bindable var photo: PhotoRecord
    @Environment(\.modelContext) private var modelContext

    /// Colonne gauche du mode développement : marges plus serrées.
    var compact: Bool = false

    @State private var presetName = ""

    private var horizontalPadding: CGFloat { compact ? 10 : 16 }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            Text("preset.header")
                .font(compact ? .subheadline.weight(.semibold) : .headline)

            HStack {
                TextField("preset.name_placeholder", text: $presetName)
                Button("preset.save") {
                    let trimmed = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let preset = PresetRecord(name: trimmed, settings: photo.developSettings)
                    modelContext.insert(preset)
                    presetName = ""
                    try? modelContext.save()
                }
                .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Button {
                NotificationCenter.default.post(name: .zenithSyncPresetToSelection, object: nil)
            } label: {
                Label(String(localized: "preset.sync_grid"), systemImage: "square.and.arrow.down.on.square")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(presets) { preset in
                        Button {
                            photo.applyDevelopSettings(preset.settings)
                            try? modelContext.save()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .foregroundStyle(.primary)
                                Text(preset.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(minHeight: compact ? 100 : 120)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, compact ? 6 : 12)
    }
}
