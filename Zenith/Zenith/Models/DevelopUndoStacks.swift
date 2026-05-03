//
//  DevelopUndoStacks.swift
//  Zenith
//

import Foundation

/// Historique non destructif local (undo / redo) des réglages de développement.
struct DevelopUndoStacks: Codable, Equatable {
    var past: [Data]
    var future: [Data]

    static let empty = DevelopUndoStacks(past: [], future: [])

    static var emptyEncodedData: Data {
        (try? JSONEncoder().encode(empty)) ?? Data()
    }

    static func decode(_ data: Data) -> DevelopUndoStacks {
        (try? JSONDecoder().decode(DevelopUndoStacks.self, from: data)) ?? .empty
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }
}

extension DevelopUndoStacks {
    /// Alias pour une sauvegarde SwiftData sans propagation d’erreur.
    var encodedDataIfPossible: Data {
        (try? encoded()) ?? Self.emptyEncodedData
    }
}
