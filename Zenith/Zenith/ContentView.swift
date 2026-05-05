//
//  ContentView.swift
//  Zenith
//
//  Created by Romain Cobigo on 02/05/2026.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        MainWorkspaceView()
            .background(ZenithTheme.pageBackground)
            .background(WindowChromeConfigurator())
            .onChange(of: scenePhase) { _, phase in
                if phase == .inactive || phase == .background {
                    try? modelContext.save()
                }
            }
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
        .modelContainer(container)
}
