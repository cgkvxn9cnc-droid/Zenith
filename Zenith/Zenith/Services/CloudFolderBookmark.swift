//
//  CloudFolderBookmark.swift
//  Zenith
//

import AppKit
import Foundation

/// Référence utilisateur à un dossier synchronisé (iCloud Drive, Dropbox, Google Drive montés comme dossiers locaux).
enum CloudFolderBookmark {
    private static let defaultsKey = "zenith.cloudFolderBookmarkData"

    static func storedBookmark() -> Data? {
        UserDefaults.standard.data(forKey: defaultsKey)
    }

    static func saveBookmark(from url: URL) throws {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        let data = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    static func resolvedURL() throws -> URL {
        guard let data = storedBookmark() else {
            throw CloudFolderError.noBookmark
        }
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        if stale { throw CloudFolderError.staleBookmark }
        return url
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    static func chooseFolderPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.prompt = String(localized: "cloud.folder.prompt")
        panel.message = String(localized: "cloud.folder.message")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }
}

enum CloudFolderError: LocalizedError {
    case noBookmark
    case staleBookmark

    var errorDescription: String? {
        switch self {
        case .noBookmark:
            return String(localized: "cloud.folder.error.none")
        case .staleBookmark:
            return String(localized: "cloud.folder.error.stale")
        }
    }
}
