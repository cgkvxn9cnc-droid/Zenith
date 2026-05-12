//
//  CatalogWelcomeView.swift
//  Zenith
//

import SwiftUI

/// Écran d'accueil affiché au lancement quand aucun catalogue n'est ouvert.
/// Permet de créer, ouvrir ou sélectionner un catalogue récent.
struct CatalogWelcomeView: View {
    @ObservedObject var catalogManager: CatalogManager

    @State private var showCreateSheet = false
    @State private var newCatalogName = ""
    @State private var errorMessage: String?

    private var isErrorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            VStack(spacing: 8) {
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 56, weight: .thin))
                    .foregroundStyle(.secondary)

                Text("welcome.title")
                    .font(.largeTitle.weight(.bold))

                Text("welcome.subtitle")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Spacer(minLength: 32)

            HStack(spacing: 16) {
                actionCard(
                    icon: "plus.rectangle.on.folder",
                    titleKey: "welcome.create",
                    subtitleKey: "welcome.create.subtitle"
                ) {
                    showCreateSheet = true
                }

                actionCard(
                    icon: "folder.badge.gearshape",
                    titleKey: "welcome.open",
                    subtitleKey: "welcome.open.subtitle"
                ) {
                    do {
                        try catalogManager.openCatalogWithPicker()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            if !catalogManager.recentCatalogs.isEmpty {
                recentsList
                    .padding(.top, 32)
            }

            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 48)
        .background(ZenithTheme.pageBackground)
        .sheet(isPresented: $showCreateSheet) {
            createCatalogSheet
        }
        .alert("welcome.error.title", isPresented: isErrorPresented) {
            Button("welcome.error.ok", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Action card

    private func actionCard(icon: String, titleKey: LocalizedStringKey, subtitleKey: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(ZenithTheme.accent)
                Text(titleKey)
                    .font(.headline)
                Text(subtitleKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 200, height: 140)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recents

    private var recentsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("welcome.recents")
                .font(.headline)
                .padding(.leading, 4)

            ForEach(catalogManager.recentCatalogs) { entry in
                recentRow(entry)
            }
        }
        .frame(maxWidth: 480, alignment: .leading)
    }

    private func recentRow(_ entry: RecentCatalogEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(entry.fileURL.path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            Text(entry.lastOpenedAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                catalogManager.removeFromRecents(entry)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.quaternary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "welcome.recents.remove"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            do {
                try catalogManager.openRecentCatalog(entry)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Create sheet

    private var createCatalogSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("welcome.create.sheet_title")
                .font(.title2.weight(.bold))

            TextField("welcome.create.name_placeholder", text: $newCatalogName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("welcome.create.cancel") {
                    newCatalogName = ""
                    showCreateSheet = false
                }
                Button("welcome.create.confirm") {
                    createCatalog()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newCatalogName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 380)
        .background(ZenithTheme.pageBackground)
    }

    private func createCatalog() {
        let trimmed = newCatalogName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "welcome.create.choose_folder")
        panel.message = String(localized: "welcome.create.choose_message")

        guard panel.runModal() == .OK, let directory = panel.url else { return }

        do {
            try catalogManager.createCatalog(name: trimmed, directory: directory)
            newCatalogName = ""
            showCreateSheet = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
