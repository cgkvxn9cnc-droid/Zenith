//
//  CatalogManager.swift
//  Zenith
//

import AppKit
import Combine
import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Gère le catalogue actif, la liste des catalogues récents et l'auto-save périodique.
@MainActor
final class CatalogManager: ObservableObject {
    // MARK: - Published state

    @Published private(set) var activeCatalog: ZenithCatalog?
    @Published private(set) var modelContainer: ModelContainer?
    @Published private(set) var recentCatalogs: [RecentCatalogEntry] = []

    // MARK: - Constants

    static let catalogExtension = "zenithcatalog"
    private static let recentsKey = "zenith.recentCatalogs"
    /// Clé `UserDefaults` : rouvrir le dernier catalogue au lancement (nécessite un bookmark).
    static let autoRestoreLastCatalogUserDefaultsKey = "zenith.autoRestoreLastCatalog"

    private static var configuredAutoSaveIntervalSeconds: TimeInterval {
        TimeInterval(ZenithCatalogAutosaveInterval.current.rawValue)
    }

    /// Préférence utilisateur : restauration du catalogue au démarrage (activée par défaut).
    static var autoRestoreLastCatalog: Bool {
        if UserDefaults.standard.object(forKey: autoRestoreLastCatalogUserDefaultsKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: autoRestoreLastCatalogUserDefaultsKey)
    }

    // MARK: - Private

    private var autoSaveTimer: Timer?
    private var terminationObserver: Any?
    private var autosavePrefsObserver: NSObjectProtocol?
    /// Dossier bundle `.zenithcatalog` avec accès security‑scoped actif tant qu’un catalogue est ouvert.
    private var securityScopedCatalogURL: URL?

    // MARK: - Init

    init() {
        loadRecents()
        setupLifecycleObservers()
    }

    /// Au premier affichage de la fenêtre : rouvre le catalogue listé en premier dans les récents si possible.
    func restoreLastCatalogIfNeeded() {
        guard Self.autoRestoreLastCatalog else { return }
        guard activeCatalog == nil else { return }
        guard let entry = recentCatalogs.first, entry.bookmarkData != nil else { return }
        try? openRecentCatalog(entry)
    }

    deinit {
        autoSaveTimer?.invalidate()
        if let obs = terminationObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = autosavePrefsObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - Public API

    /// Crée un nouveau catalogue à l'emplacement choisi et l'ouvre.
    func createCatalog(name: String, directory: URL) throws {
        stopSecurityScopedCatalogAccess()

        guard directory.startAccessingSecurityScopedResource() else {
            throw CatalogError.securityScopeDenied(directory)
        }
        defer { directory.stopAccessingSecurityScopedResource() }

        let catalogURL = directory
            .appendingPathComponent("\(name).\(Self.catalogExtension)", isDirectory: true)
            .standardizedFileURL

        let fm = FileManager.default
        if !fm.fileExists(atPath: catalogURL.path(percentEncoded: false)) {
            try fm.createDirectory(at: catalogURL, withIntermediateDirectories: true)
        }

        let bookmarkData = try Self.makeBookmarkData(forCatalogBundle: catalogURL)

        try installOpenedCatalog(bundleURL: catalogURL, displayNameIfKnown: name, bookmarkDataForRecents: bookmarkData)
        startAutoSave()
    }

    /// Ouvre un catalogue existant via le sélecteur de fichiers (accès utilisateur ⇒ security scope).
    func openCatalog(at url: URL) throws {
        stopSecurityScopedCatalogAccess()

        let bundleURL = url.standardizedFileURL
        guard bundleURL.startAccessingSecurityScopedResource() else {
            throw CatalogError.securityScopeDenied(bundleURL)
        }

        try installOpenedCatalog(bundleURLStartsAccessing: bundleURL)
        startAutoSave()
    }

    /// Rouvre un catalogue depuis la liste des récents (bookmark security‑scoped ; entrées anciennes ⇒ panneau de sélection dans le dossier parent).
    func openRecentCatalog(_ entry: RecentCatalogEntry) throws {
        guard let bookmark = entry.bookmarkData else {
            try reopenRecentWithoutBookmarkViaPicker(for: entry)
            return
        }

        stopSecurityScopedCatalogAccess()

        var stale = false
        let resolved = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ).standardizedFileURL

        guard resolved.startAccessingSecurityScopedResource() else {
            throw CatalogError.securityScopeDenied(resolved)
        }

        let bookmarkForRecents: Data
        if stale {
            do {
                bookmarkForRecents = try Self.makeBookmarkData(forCatalogBundle: resolved)
            } catch {
                resolved.stopAccessingSecurityScopedResource()
                throw error
            }
        } else {
            bookmarkForRecents = bookmark
        }

        try installOpenedCatalog(
            bundleURLStartsAccessing: resolved,
            displayNameOverride: entry.name,
            bookmarkOverrideForRecents: bookmarkForRecents
        )
        startAutoSave()
    }

    /// Présente un panneau d'ouverture de fichier et ouvre le catalogue sélectionné.
    func openCatalogWithPicker() throws {
        let panel = NSOpenPanel()
        configureCatalogOpenPanel(panel)
        panel.message = String(localized: "welcome.open.panel_message")
        panel.title = String(localized: "welcome.open.panel_title")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try openCatalog(at: url)
    }

    /// Ferme le catalogue actif en sauvegardant.
    func closeCatalog() {
        saveIfNeeded()
        stopSecurityScopedCatalogAccess()
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
        activeCatalog = nil
        modelContainer = nil
    }

    /// Supprime un catalogue récent de la liste (ne supprime pas le fichier).
    func removeFromRecents(_ entry: RecentCatalogEntry) {
        recentCatalogs.removeAll { $0.id == entry.id }
        persistRecents()
    }

    /// Indique si l'entrée correspond au catalogue actuellement ouvert.
    func isActive(_ entry: RecentCatalogEntry) -> Bool {
        guard let active = activeCatalog else { return false }
        return active.fileURL.standardizedFileURL == entry.fileURL.standardizedFileURL
    }

    /// Vérifie l'accessibilité d'un catalogue récent (présent sur disque, lisible par Zenith).
    /// L'accès security-scoped est ouvert temporairement pour vérifier l'existence puis fermé.
    func readability(of entry: RecentCatalogEntry) -> CatalogReadability {
        if isActive(entry) { return .available }

        guard let data = entry.bookmarkData else {
            let exists = FileManager.default.fileExists(atPath: entry.fileURL.path(percentEncoded: false))
            return exists ? .needsRelocation : .unreachable
        }

        var stale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return .unreachable
        }

        let granted = resolved.startAccessingSecurityScopedResource()
        defer { if granted { resolved.stopAccessingSecurityScopedResource() } }

        let exists = FileManager.default.fileExists(atPath: resolved.path(percentEncoded: false))
        return exists ? .available : .unreachable
    }

    // MARK: - Auto-save

    private func startAutoSave() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: Self.configuredAutoSaveIntervalSeconds, repeats: true) { [weak self] _ in
            guard let manager = self else { return }
            Task { @MainActor [manager] in
                manager.saveIfNeeded()
            }
        }
    }

    /// Recrée le timer si un catalogue est ouvert (appelé quand l’utilisateur change l’intervalle dans Réglages).
    private func refreshAutoSaveTimerIfRunning() {
        guard autoSaveTimer != nil else { return }
        startAutoSave()
    }

    func saveIfNeeded() {
        guard let ctx = modelContainer?.mainContext else { return }
        try? ctx.save()
    }

    // MARK: - Lifecycle

    private func setupLifecycleObservers() {
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let manager = self else { return }
            Task { @MainActor [manager] in
                manager.saveIfNeeded()
            }
        }

        autosavePrefsObserver = NotificationCenter.default.addObserver(
            forName: .zenithCatalogAutosaveIntervalChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAutoSaveTimerIfRunning()
            }
        }
    }

    // MARK: - Recents

    private func addToRecents(_ catalog: ZenithCatalog, bookmarkData: Data) {
        let entry = RecentCatalogEntry(
            id: catalog.id,
            name: catalog.name,
            fileURL: catalog.fileURL,
            lastOpenedAt: catalog.lastOpenedAt,
            bookmarkData: bookmarkData
        )
        recentCatalogs.removeAll { $0.fileURL.standardizedFileURL == entry.fileURL.standardizedFileURL }
        recentCatalogs.insert(entry, at: 0)
        if recentCatalogs.count > 10 {
            recentCatalogs = Array(recentCatalogs.prefix(10))
        }
        persistRecents()
    }

    private func loadRecents() {
        guard let data = UserDefaults.standard.data(forKey: Self.recentsKey),
              let decoded = try? JSONDecoder().decode([RecentCatalogEntry].self, from: data) else { return }
        recentCatalogs = decoded
    }

    private func persistRecents() {
        guard let data = try? JSONEncoder().encode(recentCatalogs) else { return }
        UserDefaults.standard.set(data, forKey: Self.recentsKey)
    }

    // MARK: - Container factory

    private func stopSecurityScopedCatalogAccess() {
        if let u = securityScopedCatalogURL {
            u.stopAccessingSecurityScopedResource()
            securityScopedCatalogURL = nil
        }
    }

    private func configureCatalogOpenPanel(_ panel: NSOpenPanel) {
        panel.allowedContentTypes = [.folder]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
    }

    /// Anciennes entrées récentes sans bookmark : même UX qu’une ouverture manuelle, dossier parent préaffiché.
    private func reopenRecentWithoutBookmarkViaPicker(for entry: RecentCatalogEntry) throws {
        let panel = NSOpenPanel()
        configureCatalogOpenPanel(panel)
        let parent = entry.fileURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: parent.path(percentEncoded: false)) {
            panel.directoryURL = parent
        }
        let fmtMessage = String(localized: "catalog.reopen.panel_message_format")
        panel.message = String(format: fmtMessage, locale: .current, entry.name)
        panel.title = String(localized: "catalog.reopen.panel_title")

        guard panel.runModal() == .OK, let selected = panel.url else { return }

        let expected = entry.fileURL.standardizedFileURL
        let got = selected.standardizedFileURL
        guard catalogsAreSameBundle(got, expected) else {
            throw CatalogError.recentSelectionMismatch(expectedPath: expected.path(percentEncoded: false))
        }

        try openCatalog(at: got)
    }

    private func catalogsAreSameBundle(_ a: URL, _ b: URL) -> Bool {
        a.standardizedFileURL.path(percentEncoded: false) == b.standardizedFileURL.path(percentEncoded: false)
    }

    /// À appeler après `startAccessingSecurityScopedResource()` sur le bundle catalogue.
    private func installOpenedCatalog(
        bundleURLStartsAccessing bundleURL: URL,
        displayNameOverride: String? = nil,
        bookmarkOverrideForRecents: Data? = nil
    ) throws {
        let standardized = bundleURL.standardizedFileURL
        let fm = FileManager.default
        guard fm.fileExists(atPath: standardized.path(percentEncoded: false)) else {
            bundleURL.stopAccessingSecurityScopedResource()
            throw CatalogError.fileNotFound(standardized)
        }

        let inferredName =
            displayNameOverride
            ?? standardized.deletingPathExtension().lastPathComponent
        var catalog = ZenithCatalog(name: inferredName, fileURL: standardized)
        catalog.lastOpenedAt = .now

        do {
            let container = try Self.makeContainer(at: standardized)

            let bookmarkStored: Data
            if let override = bookmarkOverrideForRecents {
                bookmarkStored = override
            } else {
                bookmarkStored = try Self.makeBookmarkData(forCatalogBundle: standardized)
            }

            securityScopedCatalogURL = standardized
            activeCatalog = catalog
            modelContainer = container
            DevelopRemovedPanelEffectsMigration.runIfNeeded(
                modelContext: container.mainContext,
                catalogBundleURL: standardized
            )
            addToRecents(catalog, bookmarkData: bookmarkStored)
        } catch {
            bundleURL.stopAccessingSecurityScopedResource()
            securityScopedCatalogURL = nil
            throw error
        }
    }

    /// Utilisée à la création : un bookmark est créé pendant que le dossier parent est encore autorisé, puis résolu pour garder uniquement une portée sur le bundle catalogue.
    private func installOpenedCatalog(bundleURL: URL, displayNameIfKnown: String, bookmarkDataForRecents: Data) throws {
        stopSecurityScopedCatalogAccess()

        var stale = false
        let resolved = try URL(
            resolvingBookmarkData: bookmarkDataForRecents,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ).standardizedFileURL

        guard resolved.startAccessingSecurityScopedResource() else {
            throw CatalogError.securityScopeDenied(resolved)
        }

        let bookmarkStored = stale ? ((try? Self.makeBookmarkData(forCatalogBundle: resolved)) ?? bookmarkDataForRecents) : bookmarkDataForRecents
        try installOpenedCatalog(bundleURLStartsAccessing: resolved, displayNameOverride: displayNameIfKnown, bookmarkOverrideForRecents: bookmarkStored)
    }

    private static func makeBookmarkData(forCatalogBundle bundleURL: URL) throws -> Data {
        do {
            return try bundleURL.standardizedFileURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw CatalogError.bookmarkCreationFailed(bundleURL)
        }
    }

    private static func makeContainer(at catalogURL: URL) throws -> ModelContainer {
        let schema = Schema([
            CollectionRecord.self,
            PhotoRecord.self,
            PresetRecord.self,
            ChatMessageRecord.self
        ])
        let storeURL = catalogURL.appendingPathComponent("Catalog.store")
        let config = ModelConfiguration(
            schema: schema,
            url: storeURL,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [config])
    }
}

// MARK: - Migration développement (cartes retirées du panneau)

/// Une fois par catalogue : neutralise les effets des outils supprimés du panneau (photos + préréglages).
private enum DevelopRemovedPanelEffectsMigration {
    private static let currentVersion = 1

    private static func storageKey(catalogBundleURL: URL) -> String {
        "zenith.migration.developRemovedPanelEffects.v\(currentVersion).\(catalogBundleURL.path(percentEncoded: false))"
    }

    @MainActor
    fileprivate static func runIfNeeded(modelContext: ModelContext, catalogBundleURL: URL) {
        let key = storageKey(catalogBundleURL: catalogBundleURL)
        guard UserDefaults.standard.integer(forKey: key) < currentVersion else { return }

        var changed = false

        if let photos = try? modelContext.fetch(FetchDescriptor<PhotoRecord>()) {
            for photo in photos {
                var s = photo.developSettings
                let before = s
                s.stripEffectsOfRemovedDevelopPanelTools()
                if s != before {
                    photo.developSettings = s
                    changed = true
                }
            }
        }

        if let presets = try? modelContext.fetch(FetchDescriptor<PresetRecord>()) {
            for preset in presets {
                var s = preset.settings
                let before = s
                s.stripEffectsOfRemovedDevelopPanelTools()
                if s != before {
                    preset.settings = s
                    changed = true
                }
            }
        }

        if changed {
            try? modelContext.save()
        }
        UserDefaults.standard.set(currentVersion, forKey: key)
    }
}

// MARK: - Readability

/// Statut d'accessibilité d'un catalogue connu de Zenith.
enum CatalogReadability: Equatable, Sendable {
    /// Catalogue présent sur disque et lisible par Zenith (security‑scoped bookmark valide).
    case available
    /// Catalogue introuvable (volume débranché, déplacé hors du sandbox, supprimé).
    case unreachable
    /// Catalogue présent mais bookmark indisponible : nécessite une relocalisation manuelle.
    case needsRelocation
}

// MARK: - Errors

enum CatalogError: LocalizedError {
    case fileNotFound(URL)
    case securityScopeDenied(URL)
    case bookmarkCreationFailed(URL)
    case recentSelectionMismatch(expectedPath: String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            let fmt = String(localized: "catalog.error.not_found_format")
            return String(format: fmt, locale: .current, url.lastPathComponent)
        case .securityScopeDenied(let url):
            let fmt = String(localized: "catalog.error.scope_denied_format")
            return String(format: fmt, locale: .current, url.lastPathComponent)
        case .bookmarkCreationFailed(let url):
            let fmt = String(localized: "catalog.error.bookmark_creation_format")
            return String(format: fmt, locale: .current, url.lastPathComponent)
        case .recentSelectionMismatch(let path):
            let fmt = String(localized: "catalog.error.recent_mismatch_format")
            return String(format: fmt, locale: .current, path)
        }
    }
}
