//
//  PresetRecord.swift
//  Zenith
//

import Foundation
import SwiftData

@Model
final class PresetRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var settingsBlob: Data
    var createdAt: Date

    init(id: UUID = UUID(), name: String, settings: DevelopSettings, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.settingsBlob = (try? settings.encoded()) ?? Data()
        self.createdAt = createdAt
    }

    var settings: DevelopSettings {
        get { DevelopSettings.decode(from: settingsBlob) }
        set { settingsBlob = (try? newValue.encoded()) ?? settingsBlob }
    }
}
