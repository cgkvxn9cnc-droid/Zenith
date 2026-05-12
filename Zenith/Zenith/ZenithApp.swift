//
//  ZenithApp.swift
//  Zenith
//
//  Created by Romain Cobigo on 02/05/2026.
//

import SwiftUI

@main
struct ZenithApp: App {
    @NSApplicationDelegateAdaptor(ZenithAppDelegate.self) private var appDelegate
    @StateObject private var catalogManager = CatalogManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(catalogManager)
        }
        /// Barre de titre intégrée : le contenu remonte sous la zone des boutons ; **ne pas** utiliser `.plain` (supprime le chrome système y compris fermer / réduire / zoom).
        .windowStyle(.hiddenTitleBar)
        .commands {
            ZenithCommands()
        }

        Settings {
            ZenithSettingsView()
                .environmentObject(catalogManager)
        }
        .defaultSize(width: 560, height: 420)
        .windowResizability(.contentSize)
    }
}
