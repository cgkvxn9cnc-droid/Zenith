//
//  ContentView.swift
//  Zenith
//
//  Created by Romain Cobigo on 02/05/2026.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var catalogManager: CatalogManager

    var body: some View {
        Group {
            if catalogManager.activeCatalog != nil, let container = catalogManager.modelContainer {
                MainWorkspaceView()
                    .modelContainer(container)
                    .background(ZenithTheme.pageBackground)
            } else {
                CatalogWelcomeView(catalogManager: catalogManager)
            }
        }
        .background(WindowChromeConfigurator())
        .onAppear {
            catalogManager.restoreLastCatalogIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background {
                catalogManager.saveIfNeeded()
            }
        }
        .environmentObject(catalogManager)
    }
}

#Preview {
    let schema = Schema([
        CollectionRecord.self,
        PhotoRecord.self,
        PresetRecord.self,
        ChatMessageRecord.self
    ])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [configuration])
    return ContentView()
        .environmentObject(CatalogManager())
        .modelContainer(container)
}
