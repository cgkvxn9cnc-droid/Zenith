//
//  ZenithCommands.swift
//  Zenith
//

import SwiftUI

struct ZenithCommands: Commands {
    @AppStorage("zenith.collaborationEnabled") private var collaborationEnabled = false

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(String(localized: "menu.file.import")) {
                NotificationCenter.default.post(name: .zenithImportPhotos, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Divider()

            Button(String(localized: "menu.file.invite")) {
                NotificationCenter.default.post(name: .zenithInviteCollaborator, object: nil)
            }

            Toggle(String(localized: "menu.collaboration.enabled"), isOn: $collaborationEnabled)

            Button(String(localized: "menu.file.export_batch")) {
                NotificationCenter.default.post(name: .zenithBatchExport, object: nil)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button(String(localized: "menu.file.backup_catalog")) {
                NotificationCenter.default.post(name: .zenithExportCatalogBackup, object: nil)
            }

            Button(String(localized: "menu.file.link_cloud_folder")) {
                NotificationCenter.default.post(name: .zenithLinkCloudFolder, object: nil)
            }
        }

        CommandGroup(after: .undoRedo) {
            Button(String(localized: "menu.edit.undo_develop")) {
                NotificationCenter.default.post(name: .zenithUndoDevelop, object: nil)
            }
            .keyboardShortcut("z", modifiers: [.command, .option])

            Button(String(localized: "menu.edit.redo_develop")) {
                NotificationCenter.default.post(name: .zenithRedoDevelop, object: nil)
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])

            Divider()

            Button(String(localized: "menu.edit.copy_develop")) {
                NotificationCenter.default.post(name: .zenithCopyDevelop, object: nil)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Button(String(localized: "menu.edit.paste_develop")) {
                NotificationCenter.default.post(name: .zenithPasteDevelop, object: nil)
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Divider()

            Button(String(localized: "menu.preset.sync")) {
                NotificationCenter.default.post(name: .zenithSyncPresetToSelection, object: nil)
            }
        }

        CommandMenu(String(localized: "window.menu.title")) {
            Button(String(localized: "menu.window.full_screen")) {
                NotificationCenter.default.post(name: .zenithToggleFullScreen, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .control])
        }
    }
}
