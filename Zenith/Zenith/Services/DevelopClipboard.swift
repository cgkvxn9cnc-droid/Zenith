//
//  DevelopClipboard.swift
//  Zenith
//

import AppKit
import Foundation

enum DevelopClipboard {
    private static let type = NSPasteboard.PasteboardType("com.zenith.develop-settings+json")

    static func copy(_ settings: DevelopSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: type)
    }

    static func paste() -> DevelopSettings? {
        guard let data = NSPasteboard.general.data(forType: type) else { return nil }
        return try? JSONDecoder().decode(DevelopSettings.self, from: data)
    }
}
