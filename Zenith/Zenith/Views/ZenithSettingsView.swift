//
//  ZenithSettingsView.swift
//  Zenith
//

import AppKit
import SwiftUI

/// Fenêtre système « Réglages » (menu Fichier / raccourci système).
struct ZenithSettingsView: View {
    @EnvironmentObject private var catalogManager: CatalogManager

    @AppStorage(ZenithPerformanceProfile.userDefaultsKey)
    private var performanceProfileRaw: String = ZenithPerformanceProfile.balanced.rawValue

    @AppStorage(ZenithPerformanceCustomTuning.enabledKey)
    private var performanceCustomTuningEnabled = false

    @AppStorage(ZenithPerformanceCustomTuning.proxyMaxKey)
    private var customProxyMaxDim: Double = 900

    @AppStorage(ZenithPerformanceCustomTuning.fullMaxKey)
    private var customFullMaxDim: Double = 4_096

    @AppStorage(ZenithPerformanceCustomTuning.sourceCapacityKey)
    private var customSourceCacheCapacity: Int = 4

    @AppStorage(ZenithPerformanceCustomTuning.thumbnailCountKey)
    private var customThumbnailCountLimit: Int = 1_200

    @AppStorage(ZenithPerformanceCustomTuning.thumbnailCostMBKey)
    private var customThumbnailCostMB: Int = 200

    @AppStorage(CatalogManager.autoRestoreLastCatalogUserDefaultsKey)
    private var autoRestoreLastCatalog: Bool = true

    @AppStorage(ZenithCatalogAutosaveInterval.userDefaultsKey)
    private var autosaveIntervalRaw: Int = ZenithCatalogAutosaveInterval.oneMinute.rawValue

    @AppStorage("zenith.libraryThumbSize")
    private var libraryThumbSize: Double = 148

    @AppStorage("zenith.leftSidebarVisible")
    private var leftSidebarVisible = true

    @AppStorage("zenith.rightSidebarVisible")
    private var rightSidebarVisible = true

    @AppStorage("zenith.filmstripVisible")
    private var filmstripVisible = true

    @AppStorage("zenith.fontScaleStep")
    private var fontScaleStep = 3

    @AppStorage("zenith.collaborationEnabled")
    private var collaborationEnabled = false

    @AppStorage("zenith.collaborationRole")
    private var collaborationRoleRaw = "edit"

    @AppStorage(ZenithAssumedRGBProfile.userDefaultsKey)
    private var assumedProfileRaw: String = ZenithAssumedRGBProfile.sRGB.rawValue

    @AppStorage(ZenithColorPreferences.useDisplayP3OutputKey)
    private var displayP3PreviewOutput = false

    @AppStorage(ZenithColorPreferences.cmykSoftProofEnabledKey)
    private var cmykSoftProofEnabled = false

    @State private var catalogApproximateBytes: Int64?

    private let libraryThumbSizeMin: Double = 96
    private let libraryThumbSizeMax: Double = 320
    private let fontScaleRange = 0...6

    private var performanceProfile: ZenithPerformanceProfile {
        ZenithPerformanceProfile(rawValue: performanceProfileRaw) ?? .balanced
    }

    var body: some View {
        TabView {
            interfaceTab
            colorManagementTab
            performanceTab
            catalogTab
        }
        .frame(minWidth: 520, minHeight: 380)
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Interface

    private var interfaceTab: some View {
        Form {
            Section {
                Slider(
                    value: $libraryThumbSize,
                    in: libraryThumbSizeMin ... libraryThumbSizeMax,
                    step: 4
                ) {
                    Text("settings.interface.library_thumb")
                } minimumValueLabel: {
                    Text(verbatim: "\(Int(libraryThumbSizeMin))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text(verbatim: "\(Int(libraryThumbSizeMax))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(String(format: String(localized: "settings.interface.library_thumb.format"), locale: .current, Int(libraryThumbSize)))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(String(localized: "settings.interface.left_sidebar"), isOn: $leftSidebarVisible)
                Toggle(String(localized: "settings.interface.right_sidebar"), isOn: $rightSidebarVisible)
                Toggle(String(localized: "settings.interface.filmstrip"), isOn: $filmstripVisible)

                Stepper(value: $fontScaleStep, in: fontScaleRange) {
                    Text(String(format: String(localized: "settings.interface.font_scale.format"), locale: .current, fontScaleStep, fontScaleRange.upperBound))
                }
            } header: {
                Text("settings.interface.section")
            } footer: {
                Text("settings.interface.font_scale.footer")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(String(localized: "settings.interface.collaboration.enabled"), isOn: $collaborationEnabled)
                Picker("settings.interface.collaboration.role", selection: $collaborationRoleRaw) {
                    Text("collaboration.role.read").tag("read")
                    Text("collaboration.role.edit").tag("edit")
                }
                .pickerStyle(.segmented)
                .disabled(!collaborationEnabled)
            } header: {
                Text("settings.interface.collaboration.section")
            } footer: {
                Text("settings.interface.collaboration.footer")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .tabItem {
            Label(String(localized: "settings.tab.interface"), systemImage: "macwindow")
        }
    }

    // MARK: - Couleur (espace colorimétrique)

    private var colorManagementTab: some View {
        Form {
            Section {
                Picker("settings.color.assumed.picker", selection: $assumedProfileRaw) {
                    ForEach(ZenithAssumedRGBProfile.allCases) { profile in
                        Text(LocalizedStringKey(profile.settingsLabelKey))
                            .tag(profile.rawValue)
                    }
                }
                .onChange(of: assumedProfileRaw) { _, _ in
                    postColorPreferencesChanged()
                }
            } header: {
                Text("settings.color.source.section")
            } footer: {
                Text("settings.color.source.footer")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(String(localized: "settings.color.display_p3"), isOn: $displayP3PreviewOutput)
                    .onChange(of: displayP3PreviewOutput) { _, _ in
                        postColorPreferencesChanged()
                    }

                Toggle(String(localized: "settings.color.cmyk_softproof"), isOn: $cmykSoftProofEnabled)
                    .onChange(of: cmykSoftProofEnabled) { _, _ in
                        postColorPreferencesChanged()
                    }
            } header: {
                Text("settings.color.preview.section")
            } footer: {
                Text("settings.color.preview.footer")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .tabItem {
            Label(String(localized: "settings.tab.color"), systemImage: "paintpalette")
        }
    }

    // MARK: - Performance

    private var performanceTab: some View {
        Form {
            Section {
                Picker(selection: $performanceProfileRaw) {
                    ForEach(ZenithPerformanceProfile.allCases) { profile in
                        Text(LocalizedStringKey(profile.titleKey))
                            .tag(profile.rawValue)
                    }
                } label: {
                    Text("settings.performance.profile_picker")
                }
                .pickerStyle(.inline)
                .disabled(performanceCustomTuningEnabled)
                .onChange(of: performanceProfileRaw) { _, _ in
                    applyPerformanceCachesRefresh()
                }

                Text(LocalizedStringKey(performanceProfile.detailKey))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("settings.section.performance")
            } footer: {
                Text("settings.performance.section.footer")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(String(localized: "settings.performance.custom_mode"), isOn: $performanceCustomTuningEnabled)
                    .onChange(of: performanceCustomTuningEnabled) { _, enabled in
                        if enabled {
                            ZenithPerformanceCustomTuning.copyCurrentProfileNumericLimitsToUserDefaults()
                            syncCustomBindingsFromUserDefaults()
                        }
                        applyPerformanceCachesRefresh()
                    }

                if performanceCustomTuningEnabled {
                    Slider(value: $customProxyMaxDim, in: 480 ... 2_000, step: 20) {
                        Text("settings.performance.custom_proxy")
                    }
                    .onChange(of: customProxyMaxDim) { _, _ in applyPerformanceCachesRefresh() }

                    Slider(value: $customFullMaxDim, in: 1_024 ... 8_192, step: 256) {
                        Text("settings.performance.custom_full")
                    }
                    .onChange(of: customFullMaxDim) { _, _ in applyPerformanceCachesRefresh() }

                    Stepper(value: $customSourceCacheCapacity, in: 1 ... 12) {
                        Text(String(format: String(localized: "settings.performance.custom_source_capacity.format"), locale: .current, customSourceCacheCapacity))
                    }
                    .onChange(of: customSourceCacheCapacity) { _, _ in applyPerformanceCachesRefresh() }

                    Stepper(value: $customThumbnailCountLimit, in: 200 ... 6_000, step: 50) {
                        Text(String(format: String(localized: "settings.performance.custom_thumb_count.format"), locale: .current, customThumbnailCountLimit))
                    }
                    .onChange(of: customThumbnailCountLimit) { _, _ in applyPerformanceCachesRefresh() }

                    Stepper(value: $customThumbnailCostMB, in: 32 ... 512, step: 8) {
                        Text(String(format: String(localized: "settings.performance.custom_thumb_memory.format"), locale: .current, customThumbnailCostMB))
                    }
                    .onChange(of: customThumbnailCostMB) { _, _ in applyPerformanceCachesRefresh() }
                }
            } footer: {
                Text("settings.performance.custom_mode.footer")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(String(localized: "settings.performance.clear_caches")) {
                    DevelopPreviewCache.shared.invalidate()
                    ThumbnailCache.shared.reapplyLimitsFromPreferences(clearEntries: true)
                }
                .help(String(localized: "settings.performance.clear_caches.help"))
            } footer: {
                Text("settings.performance.clear_caches.footer")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .tabItem {
            Label(String(localized: "settings.tab.performance"), systemImage: "gauge.with.dots.needle.67percent")
        }
    }

    // MARK: - Catalogue

    private var catalogTab: some View {
        Form {
            if let catalog = catalogManager.activeCatalog {
                Section {
                    LabeledContent(String(localized: "settings.catalog.active_name")) {
                        Text(catalog.name)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }
                    LabeledContent(String(localized: "settings.catalog.active_path")) {
                        Text(catalog.fileURL.path)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(4)
                    }
                    if let bytes = catalogApproximateBytes {
                        LabeledContent(String(localized: "settings.catalog.approximate_size")) {
                            Text(formattedByteCount(bytes))
                        }
                    }
                    Button(String(localized: "settings.catalog.show_in_finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([catalog.fileURL])
                    }
                } header: {
                    Text("settings.catalog.active_section")
                } footer: {
                    Text("settings.catalog.active_section.footer")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .task(id: catalog.id) {
                    catalogApproximateBytes = nil
                    let url = catalog.fileURL
                    catalogApproximateBytes = await Task.detached {
                        CatalogDirectoryByteCounter.bytes(at: url)
                    }.value
                }
            } else {
                Section {
                    Text("settings.catalog.no_catalog_open")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("settings.catalog.active_section")
                }
            }

            Section {
                Toggle(String(localized: "settings.catalog.auto_restore"), isOn: $autoRestoreLastCatalog)
            } header: {
                Text("settings.section.catalog")
            } footer: {
                Text("settings.catalog.auto_restore.footer")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker(selection: $autosaveIntervalRaw) {
                    ForEach(ZenithCatalogAutosaveInterval.allCases) { interval in
                        Text(LocalizedStringKey(interval.labelKey))
                            .tag(interval.rawValue)
                    }
                } label: {
                    Text("settings.catalog.autosave_picker")
                }
                .onChange(of: autosaveIntervalRaw) { _, _ in
                    NotificationCenter.default.post(name: .zenithCatalogAutosaveIntervalChanged, object: nil)
                }
            } footer: {
                Text("settings.catalog.autosave.footer")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .tabItem {
            Label(String(localized: "settings.tab.catalog"), systemImage: "folder.badge.gearshape")
        }
    }

    private func formattedByteCount(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    private func applyPerformanceCachesRefresh() {
        DevelopPreviewCache.shared.invalidate()
        ThumbnailCache.shared.reapplyLimitsFromPreferences(clearEntries: true)
    }

    private func postColorPreferencesChanged() {
        NotificationCenter.default.post(name: .zenithColorPreferencesDidChange, object: nil)
        DevelopPreviewCache.shared.invalidate()
        ThumbnailCache.shared.clear()
    }

    /// Après `copyCurrentProfileNumericLimitsToUserDefaults`, ramène les `@AppStorage` sur les valeurs écrites.
    private func syncCustomBindingsFromUserDefaults() {
        let d = UserDefaults.standard
        customProxyMaxDim = d.double(forKey: ZenithPerformanceCustomTuning.proxyMaxKey)
        customFullMaxDim = d.double(forKey: ZenithPerformanceCustomTuning.fullMaxKey)
        customSourceCacheCapacity = d.integer(forKey: ZenithPerformanceCustomTuning.sourceCapacityKey)
        customThumbnailCountLimit = d.integer(forKey: ZenithPerformanceCustomTuning.thumbnailCountKey)
        customThumbnailCostMB = d.integer(forKey: ZenithPerformanceCustomTuning.thumbnailCostMBKey)
    }
}

// MARK: - Taille catalogue (hors MainActor)

private enum CatalogDirectoryByteCounter {
    nonisolated static func bytes(at root: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir) else { return 0 }
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let item as URL in enumerator {
            do {
                let rv = try item.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if rv.isRegularFile == true, let s = rv.fileSize {
                    total += Int64(s)
                }
            } catch {
                continue
            }
        }
        return total
    }
}
