//
//  ZenithApp.swift
//  Zenith
//
//  Created by Romain Cobigo on 02/05/2026.
//

import SwiftData
import SwiftUI

@main
struct ZenithApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            CollectionRecord.self,
            PhotoRecord.self,
            PresetRecord.self,
            ChatMessageRecord.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .commands {
            ZenithCommands()
        }
    }
}
