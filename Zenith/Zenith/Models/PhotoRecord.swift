//
//  PhotoRecord.swift
//  Zenith
//

import Foundation
import SwiftData

enum PhotoPickFlag: String, Codable, CaseIterable {
    case none
    case pick
    case reject
}

private let maxDevelopUndoSteps = 50

@Model
final class PhotoRecord {
    @Attribute(.unique) var id: UUID
    /// Signet sécurisé sandbox pour accéder au fichier original.
    var fileBookmark: Data
    var filename: String
    /// 0–5 étoiles.
    var rating: Int
    var flagRaw: String
    var collectionID: UUID?
    var developBlob: Data
    /// Filets undo/redo des clichés `developBlob`.
    var undoStackBlob: Data
    var addedAt: Date
    var pixelWidth: Int
    var pixelHeight: Int

    init(
        id: UUID = UUID(),
        fileBookmark: Data,
        filename: String,
        rating: Int = 0,
        flag: PhotoPickFlag = .none,
        collectionID: UUID? = nil,
        developBlob: Data = DevelopSettings.neutralEncodedData,
        undoStackBlob: Data = DevelopUndoStacks.emptyEncodedData,
        addedAt: Date = Date(),
        pixelWidth: Int = 0,
        pixelHeight: Int = 0
    ) {
        self.id = id
        self.fileBookmark = fileBookmark
        self.filename = filename
        self.rating = rating
        self.flagRaw = flag.rawValue
        self.collectionID = collectionID
        self.developBlob = developBlob
        self.undoStackBlob = undoStackBlob
        self.addedAt = addedAt
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    var flag: PhotoPickFlag {
        get { PhotoPickFlag(rawValue: flagRaw) ?? .none }
        set { flagRaw = newValue.rawValue }
    }

    var developSettings: DevelopSettings {
        get { DevelopSettings.decode(from: developBlob) }
        set { developBlob = (try? newValue.encoded()) ?? developBlob }
    }

    /// Applique des réglages et empile l’état précédente pour l’historique non destructif.
    func applyDevelopSettings(_ newValue: DevelopSettings) {
        let current = developSettings
        guard current != newValue else { return }
        var stacks = DevelopUndoStacks.decode(undoStackBlob)
        if stacks.past.count >= maxDevelopUndoSteps {
            stacks.past.removeFirst()
        }
        stacks.past.append(developBlob)
        stacks.future.removeAll()
        developBlob = (try? newValue.encoded()) ?? developBlob
        undoStackBlob = (try? stacks.encoded()) ?? undoStackBlob
    }

    func undoDevelop() -> Bool {
        var stacks = DevelopUndoStacks.decode(undoStackBlob)
        guard let previous = stacks.past.popLast() else { return false }
        stacks.future.append(developBlob)
        developBlob = previous
        undoStackBlob = (try? stacks.encoded()) ?? undoStackBlob
        return true
    }

    func redoDevelop() -> Bool {
        var stacks = DevelopUndoStacks.decode(undoStackBlob)
        guard let next = stacks.future.popLast() else { return false }
        stacks.past.append(developBlob)
        developBlob = next
        undoStackBlob = (try? stacks.encoded()) ?? undoStackBlob
        return true
    }

    var canUndoDevelop: Bool {
        !DevelopUndoStacks.decode(undoStackBlob).past.isEmpty
    }

    var canRedoDevelop: Bool {
        !DevelopUndoStacks.decode(undoStackBlob).future.isEmpty
    }

    func resetDevelopToNeutral() {
        developBlob = DevelopSettings.neutralEncodedData
        undoStackBlob = DevelopUndoStacks.emptyEncodedData
    }
}
