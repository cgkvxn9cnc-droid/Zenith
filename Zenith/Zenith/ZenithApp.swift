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
    @NSApplicationDelegateAdaptor(ZenithAppDelegate.self) private var appDelegate

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
        /// Barre de titre intégrée : le contenu remonte sous la zone des boutons ; **ne pas** utiliser `.plain` (supprime le chrome système y compris fermer / réduire / zoom).
        .windowStyle(.hiddenTitleBar)
        .modelContainer(sharedModelContainer)
        .commands {
            ZenithCommands()
        }
    }
}
