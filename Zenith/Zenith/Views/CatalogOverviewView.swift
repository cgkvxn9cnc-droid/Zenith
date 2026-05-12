//
//  CatalogOverviewView.swift
//  Zenith
//

import SwiftUI

/// Dashboard du catalogue : statistiques, santé, catalogues connus, actions rapides.
struct CatalogOverviewView: View {
    let photoCount: Int
    let collectionFolderCount: Int
    let onImportPhotos: () -> Void
    let onImportLightroom: () -> Void

    @EnvironmentObject private var catalogManager: CatalogManager

    @AppStorage("zenith.lastAutoSave") private var lastAutoSaveTimestamp: Double = 0
    /// Bouton « Actualiser » : incrémenter ce compteur force la ré-évaluation des disponibilités.
    @State private var availabilityRefreshToken = 0
    @State private var openErrorMessage: String?

    private var isOpenErrorPresented: Binding<Bool> {
        Binding(
            get: { openErrorMessage != nil },
            set: { if !$0 { openErrorMessage = nil } }
        )
    }

    private var lastAutoSaveDate: Date? {
        lastAutoSaveTimestamp > 0 ? Date(timeIntervalSince1970: lastAutoSaveTimestamp) : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                headerSection

                statsGrid

                healthSection

                openedCatalogsSection

                actionsSection
            }
            /// Maintenant que la page Catalogue n’a plus de colonnes latérales, on lui offre une largeur confortable
            /// (≤ 1080 pt) et on la centre dans la fenêtre pour conserver l’équilibre visuel d’origine.
            .frame(maxWidth: 1080, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(ZenithTheme.pageBackground)
        .alert("welcome.error.title", isPresented: isOpenErrorPresented) {
            Button("welcome.error.ok", role: .cancel) { openErrorMessage = nil }
        } message: {
            Text(openErrorMessage ?? "")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("catalog.overview.title")
                .font(.system(size: 40, weight: .bold))

            Text("catalog.overview.body")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Stats

    /// Trois blocs statistiques : occupent maintenant chacun la même largeur et respirent davantage.
    private var statsGrid: some View {
        HStack(spacing: 20) {
            statBlock(value: "\(photoCount)", labelKey: "catalog.overview.stat_photos", icon: "photo.on.rectangle.angled")
            statBlock(value: "\(collectionFolderCount)", labelKey: "catalog.overview.stat_collections", icon: "folder")
            statBlock(value: formattedDiskSize, labelKey: "catalog.overview.stat_size", icon: "internaldrive")
        }
    }

    private var formattedDiskSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let bytes = Int64(photoCount) * 28_000
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Health

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("catalog.overview.health")
                .font(.title2.weight(.semibold))

            HStack(spacing: 10) {
                Image(systemName: catalogHealthIcon)
                    .font(.title3)
                    .foregroundStyle(catalogHealthColor)
                Text(catalogHealthLabel)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            if let date = lastAutoSaveDate {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                    Text("catalog.overview.last_save \(date, style: .relative)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.04)))
    }

    private var catalogHealthIcon: String {
        photoCount > 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var catalogHealthColor: Color {
        photoCount > 0 ? .green : .orange
    }

    private var catalogHealthLabel: LocalizedStringKey {
        photoCount > 0 ? "catalog.overview.health_ok" : "catalog.overview.health_empty"
    }

    // MARK: - Opened catalogs (recents + availability)

    /// Liste des catalogues que Zenith a déjà ouverts, avec un voyant signalant si chacun est actuellement lisible.
    private var openedCatalogsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("catalog.overview.opened_section")
                    .font(.title2.weight(.semibold))
                Spacer(minLength: 0)
                Button {
                    availabilityRefreshToken &+= 1
                } label: {
                    Label("catalog.overview.opened_section.refresh", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                .controlSize(.regular)
                .help(String(localized: "catalog.overview.opened_section.refresh"))
            }

            Text("catalog.overview.opened_section.help")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if catalogManager.recentCatalogs.isEmpty {
                Text("catalog.overview.opened_section.empty")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 8) {
                    ForEach(catalogManager.recentCatalogs) { entry in
                        catalogRow(for: entry)
                    }
                }
                .id(availabilityRefreshToken)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.04)))
    }

    @ViewBuilder
    private func catalogRow(for entry: RecentCatalogEntry) -> some View {
        let isActive = catalogManager.isActive(entry)
        let readability: CatalogReadability = isActive ? .available : catalogManager.readability(of: entry)
        HStack(alignment: .center, spacing: 10) {
            statusDot(for: readability, isActive: isActive)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if isActive {
                        Text("catalog.overview.opened_section.active_badge")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(ZenithTheme.accent)
                            )
                    }
                }
                Text(entry.fileURL.path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text(readabilityLabel(readability, isActive: isActive))
                    .font(.caption2)
                    .foregroundStyle(readabilityColor(readability, isActive: isActive))
            }

            Spacer(minLength: 8)

            Text(entry.lastOpenedAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !isActive {
                Button {
                    do {
                        try catalogManager.openRecentCatalog(entry)
                    } catch {
                        openErrorMessage = error.localizedDescription
                    }
                } label: {
                    Image(systemName: readability == .available ? "arrow.up.right.square" : "questionmark.folder")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(readability == .unreachable ? Color.secondary : ZenithTheme.accent)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(String(localized: String.LocalizationValue(
                    readability == .available
                        ? "catalog.overview.opened_section.open"
                        : "catalog.overview.opened_section.locate"
                )))
                .disabled(readability == .unreachable && entry.bookmarkData == nil)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(isActive ? 0.08 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isActive ? ZenithTheme.accent.opacity(0.55) : Color.primary.opacity(0.06),
                    lineWidth: 1
                )
        )
    }

    private func statusDot(for readability: CatalogReadability, isActive: Bool) -> some View {
        Circle()
            .fill(readabilityColor(readability, isActive: isActive))
            .frame(width: 9, height: 9)
            .overlay(
                Circle()
                    .strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5)
            )
            .help(readabilityHelp(readability, isActive: isActive))
    }

    private func readabilityColor(_ readability: CatalogReadability, isActive: Bool) -> Color {
        if isActive { return .green }
        switch readability {
        case .available: return .green
        case .needsRelocation: return .orange
        case .unreachable: return .red
        }
    }

    private func readabilityLabel(_ readability: CatalogReadability, isActive: Bool) -> String {
        if isActive { return String(localized: "catalog.overview.opened_section.status.active") }
        switch readability {
        case .available: return String(localized: "catalog.overview.opened_section.status.available")
        case .needsRelocation: return String(localized: "catalog.overview.opened_section.status.needs_relocation")
        case .unreachable: return String(localized: "catalog.overview.opened_section.status.unreachable")
        }
    }

    private func readabilityHelp(_ readability: CatalogReadability, isActive: Bool) -> String {
        if isActive { return String(localized: "catalog.overview.opened_section.status.active") }
        switch readability {
        case .available: return String(localized: "catalog.overview.opened_section.status.available")
        case .needsRelocation: return String(localized: "catalog.overview.opened_section.status.needs_relocation")
        case .unreachable: return String(localized: "catalog.overview.opened_section.status.unreachable")
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("catalog.overview.actions")
                .font(.title2.weight(.semibold))

            HStack(spacing: 14) {
                Button {
                    onImportPhotos()
                } label: {
                    Label("catalog.overview.import", systemImage: "square.and.arrow.down")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)

                Button {
                    onImportLightroom()
                } label: {
                    Label("catalog.overview.import_lightroom", systemImage: "camera.aperture")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.extraLarge)

                Button {
                    NotificationCenter.default.post(name: .zenithExportCatalogBackup, object: nil)
                } label: {
                    Label("catalog.overview.backup", systemImage: "arrow.down.doc")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.extraLarge)
            }
        }
    }

    // MARK: - Stat block

    /// Bloc statistique unitaire : prend toute la largeur disponible (`maxWidth: .infinity`) pour exploiter la nouvelle largeur de page.
    private func statBlock(value: String, labelKey: LocalizedStringKey, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 36, weight: .semibold))
                .monospacedDigit()
            Text(labelKey)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}
