//
//  PresetsPanel.swift
//  Zenith
//

import SwiftData
import SwiftUI

struct PresetsPanel: View {
    @Query(sort: \PresetRecord.createdAt, order: .reverse) private var presets: [PresetRecord]
    @Bindable var photo: PhotoRecord
    /// Photos additionnelles couvertes par « Appliquer à la sélection » (vide ⇒ ne s'applique qu'à `photo`).
    var selectionTargets: [PhotoRecord] = []
    @Environment(\.modelContext) private var modelContext

    /// Colonne gauche du mode développement : marges plus serrées.
    var compact: Bool = false

    @State private var presetName = ""
    @State private var renamingPreset: PresetRecord?
    @State private var renameDraft = ""
    @FocusState private var nameFieldFocused: Bool

    private var horizontalPadding: CGFloat { compact ? 10 : 16 }

    /// Cible(s) effective(s) pour « Appliquer à la sélection » : duplique `photo` si la multi-sélection est vide.
    private var effectiveSelectionTargets: [PhotoRecord] {
        if !selectionTargets.isEmpty { return selectionTargets }
        return [photo]
    }

    private var isMultiSelection: Bool {
        let unique = Set(effectiveSelectionTargets.map(\.id))
        return unique.count > 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            header
            saveBlock
            if presets.isEmpty {
                emptyState
            } else {
                presetList
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, compact ? 8 : 12)
        .alert(String(localized: "preset.rename.title"),
               isPresented: Binding(get: { renamingPreset != nil }, set: { if !$0 { renamingPreset = nil } })) {
            TextField(String(localized: "preset.name_placeholder"), text: $renameDraft)
            Button(String(localized: "preset.rename.confirm")) { commitRename() }
                .keyboardShortcut(.defaultAction)
            Button(String(localized: "common.cancel"), role: .cancel) { renamingPreset = nil }
        } message: {
            Text("preset.rename.message")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(String(localized: "preset.header"), systemImage: "wand.and.stars")
                .font(compact ? .subheadline.weight(.semibold) : .headline)
                .labelStyle(.titleAndIcon)
            Spacer(minLength: 0)
            if !presets.isEmpty {
                Text("\(presets.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.08)))
            }
        }
    }

    // MARK: - Save

    private var saveBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField(String(localized: "preset.name_placeholder"), text: $presetName)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFieldFocused)
                    .onSubmit { commitNewPreset() }
                Button {
                    commitNewPreset()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(canSave ? ZenithTheme.accent : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .help(String(localized: "preset.save.help"))
                .accessibilityLabel(Text("preset.save.help"))
            }
            Text("preset.save.hint")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var canSave: Bool {
        !presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func commitNewPreset() {
        let trimmed = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let preset = PresetRecord(name: trimmed, settings: photo.developSettings)
        modelContext.insert(preset)
        presetName = ""
        nameFieldFocused = false
        try? modelContext.save()
    }

    // MARK: - List

    private var presetList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(presets) { preset in
                    presetRow(preset)
                }
            }
        }
        .frame(minHeight: compact ? 120 : 160, maxHeight: compact ? 220 : 280)
    }

    private func presetRow(_ preset: PresetRecord) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(ZenithTheme.accent.opacity(0.16))
                Image(systemName: "wand.and.stars.inverse")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ZenithTheme.accent)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(preset.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Menu {
                Button {
                    apply(preset, to: [photo])
                } label: {
                    Label(String(localized: "preset.menu.apply_focus"), systemImage: "wand.and.rays")
                }
                if isMultiSelection {
                    Button {
                        apply(preset, to: effectiveSelectionTargets)
                    } label: {
                        let format = String(localized: "preset.menu.apply_selection_format")
                        let label = String(format: format, locale: .current, effectiveSelectionTargets.count)
                        Label {
                            Text(label)
                        } icon: {
                            Image(systemName: "rectangle.stack.fill.badge.plus")
                        }
                    }
                }
                Divider()
                Button {
                    renameDraft = preset.name
                    renamingPreset = preset
                } label: {
                    Label(String(localized: "preset.menu.rename"), systemImage: "pencil")
                }
                Button(role: .destructive) {
                    delete(preset)
                } label: {
                    Label(String(localized: "preset.menu.delete"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22, height: 22)
            .help(String(localized: "preset.menu.help"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture(count: 2) {
            apply(preset, to: isMultiSelection ? effectiveSelectionTargets : [photo])
        }
        .help(String(localized: "preset.row.help"))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(String(localized: "preset.empty.title"), systemImage: "tray")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Text("preset.empty.body")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    private func apply(_ preset: PresetRecord, to targets: [PhotoRecord]) {
        let settings = preset.settings
        for target in targets {
            target.applyDevelopSettings(settings)
        }
        try? modelContext.save()
    }

    private func delete(_ preset: PresetRecord) {
        modelContext.delete(preset)
        try? modelContext.save()
    }

    private func commitRename() {
        guard let preset = renamingPreset else { return }
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            preset.name = trimmed
            try? modelContext.save()
        }
        renamingPreset = nil
        renameDraft = ""
    }
}
