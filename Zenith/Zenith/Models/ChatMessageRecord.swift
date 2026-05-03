//
//  ChatMessageRecord.swift
//  Zenith
//

import Foundation
import SwiftData

@Model
final class ChatMessageRecord {
    var id: UUID
    var author: String
    var body: String
    var sentAt: Date
    var mentionedPhotoID: UUID?
    var sharedPresetID: UUID?

    init(
        id: UUID = UUID(),
        author: String,
        body: String,
        sentAt: Date = Date(),
        mentionedPhotoID: UUID? = nil,
        sharedPresetID: UUID? = nil
    ) {
        self.id = id
        self.author = author
        self.body = body
        self.sentAt = sentAt
        self.mentionedPhotoID = mentionedPhotoID
        self.sharedPresetID = sharedPresetID
    }
}
