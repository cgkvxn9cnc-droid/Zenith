//
//  AppNotifications.swift
//  Zenith
//

import Foundation

extension Notification.Name {
    static let zenithImportPhotos = Notification.Name("zenith.importPhotos")
    static let zenithBatchExport = Notification.Name("zenith.batchExport")
    static let zenithInviteCollaborator = Notification.Name("zenith.inviteCollaborator")
    static let zenithToggleFullScreen = Notification.Name("zenith.toggleFullScreen")
    static let zenithUndoDevelop = Notification.Name("zenith.undoDevelop")
    static let zenithRedoDevelop = Notification.Name("zenith.redoDevelop")
    static let zenithCopyDevelop = Notification.Name("zenith.copyDevelop")
    static let zenithPasteDevelop = Notification.Name("zenith.pasteDevelop")
    static let zenithSyncPresetToSelection = Notification.Name("zenith.syncPresetToSelection")
    static let zenithExportCatalogBackup = Notification.Name("zenith.exportCatalogBackup")
    static let zenithLinkCloudFolder = Notification.Name("zenith.linkCloudFolder")
    static let zenithShowCatalogOverview = Notification.Name("zenith.showCatalogOverview")
    static let zenithScrollToRemoveColor = Notification.Name("zenithScrollToRemoveColor")
}
