//
//  SecurityScopedURL.swift
//  Zenith
//

import Foundation

enum BookmarkResolutionError: Error {
    case stale
}

extension PhotoRecord {
    func resolvedURL() throws -> URL {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: fileBookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        if stale { throw BookmarkResolutionError.stale }
        return url
    }
}

enum SecurityScoped {
    static func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}
