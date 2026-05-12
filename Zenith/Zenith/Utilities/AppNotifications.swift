//
//  AppNotifications.swift
//  Zenith
//

import Foundation

extension Notification.Name {
    static let zenithImportPhotos = Notification.Name("zenith.importPhotos")
    static let zenithImportLightroomCatalog = Notification.Name("zenith.importLightroomCatalog")
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
    /// Fait défiler le panneau Développement jusqu’à la carte « Grain et bruit ».
    static let zenithScrollDevelopGrainNoise = Notification.Name("zenithScrollDevelopGrainNoise")
    static let zenithCenterPreview = Notification.Name("zenith.centerPreview")
    /// L’utilisateur a modifié l’intervalle d’auto-sauvegarde du catalogue dans Réglages.
    static let zenithCatalogAutosaveIntervalChanged = Notification.Name("zenith.catalogAutosaveIntervalChanged")
    /// Préférences couleur (profil assumé, P3, preuve CMJN) : invalider caches aperçu / miniatures.
    static let zenithColorPreferencesDidChange = Notification.Name("zenith.colorPreferencesDidChange")
}
