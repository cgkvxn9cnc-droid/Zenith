//
//  ZenithPreferences.swift
//  Zenith
//

import CoreGraphics
import Foundation

/// Profil CPU / mémoire pour l’aperçu développement et le cache des miniatures.
nonisolated enum ZenithPerformanceProfile: String, CaseIterable, Identifiable, Sendable {
    /// Moins de RAM, aperçu plus léger, scroll bibliothèque plus fluide sur machine modeste.
    case efficiency
    /// Compromis par défaut.
    case balanced
    /// Aperçu plus net et cache plus large (machines avec beaucoup de RAM).
    case quality

    var id: String { rawValue }

    static let userDefaultsKey = "zenith.performanceProfile"

    nonisolated static var current: ZenithPerformanceProfile {
        get {
            let raw = UserDefaults.standard.string(forKey: userDefaultsKey) ?? ""
            return Self(rawValue: raw) ?? .balanced
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey)
        }
    }

    var titleKey: String {
        switch self {
        case .efficiency: "settings.performance.efficiency"
        case .balanced: "settings.performance.balanced"
        case .quality: "settings.performance.quality"
        }
    }

    var detailKey: String {
        switch self {
        case .efficiency: "settings.performance.efficiency.detail"
        case .balanced: "settings.performance.balanced.detail"
        case .quality: "settings.performance.quality.detail"
        }
    }

    /// Taille max du côté long pour l’aperçu « proxy » (curseurs en mouvement).
    var developProxyMaxDimension: CGFloat {
        switch self {
        case .efficiency: 720
        case .balanced: 900
        case .quality: 1200
        }
    }

    /// Taille max du côté long pour l’aperçu pleine résolution.
    var developFullMaxDimension: CGFloat {
        switch self {
        case .efficiency: 2_048
        case .balanced: 4_096
        case .quality: 6_144
        }
    }

    /// Nombre d’images sources RAW/CI gardées en LRU dans `DevelopPreviewCache`.
    var developSourceCacheCapacity: Int {
        switch self {
        case .efficiency: 2
        case .balanced: 4
        case .quality: 6
        }
    }

    var thumbnailCacheCountLimit: Int {
        switch self {
        case .efficiency: 600
        case .balanced: 1_200
        case .quality: 2_000
        }
    }

    /// Limite de coût pour `NSCache` (miniatures JPEG décodées), en octets.
    var thumbnailCacheCostLimitBytes: Int {
        switch self {
        case .efficiency: 120 * 1024 * 1024
        case .balanced: 200 * 1024 * 1024
        case .quality: 320 * 1024 * 1024
        }
    }
}

/// Clés `UserDefaults` pour le mode performance **personnalisé** (surcharge des valeurs du profil prédéfini).
nonisolated enum ZenithPerformanceCustomTuning {
    static let enabledKey = "zenith.performanceCustomTuningEnabled"
    static let proxyMaxKey = "zenith.performanceCustomProxyMaxDim"
    static let fullMaxKey = "zenith.performanceCustomFullMaxDim"
    static let sourceCapacityKey = "zenith.performanceCustomDevelopSourceCacheCapacity"
    static let thumbnailCountKey = "zenith.performanceCustomThumbnailCountLimit"
    static let thumbnailCostMBKey = "zenith.performanceCustomThumbnailCostMB"

    /// Recopie les limites numériques du profil courant dans les surcharges (typiquement à l’activation du mode personnalisé).
    nonisolated static func copyCurrentProfileNumericLimitsToUserDefaults() {
        let p = ZenithPerformanceProfile.current
        let d = UserDefaults.standard
        d.set(Double(p.developProxyMaxDimension), forKey: proxyMaxKey)
        d.set(Double(p.developFullMaxDimension), forKey: fullMaxKey)
        d.set(p.developSourceCacheCapacity, forKey: sourceCapacityKey)
        d.set(p.thumbnailCacheCountLimit, forKey: thumbnailCountKey)
        let mb = max(32, p.thumbnailCacheCostLimitBytes / (1024 * 1024))
        d.set(mb, forKey: thumbnailCostMBKey)
    }
}

/// Limites effectives pour l’aperçu développement et le cache des miniatures (profil ou personnalisé).
nonisolated enum ZenithEffectivePerformance {
    nonisolated static var isCustomTuningEnabled: Bool {
        UserDefaults.standard.bool(forKey: ZenithPerformanceCustomTuning.enabledKey)
    }

    nonisolated static var developProxyMaxDimension: CGFloat {
        guard isCustomTuningEnabled else {
            return ZenithPerformanceProfile.current.developProxyMaxDimension
        }
        let d = UserDefaults.standard.double(forKey: ZenithPerformanceCustomTuning.proxyMaxKey)
        let fallback = Double(ZenithPerformanceProfile.current.developProxyMaxDimension)
        let v = d > 0 ? d : fallback
        return CGFloat(min(max(v, 480), 2_000))
    }

    nonisolated static var developFullMaxDimension: CGFloat {
        guard isCustomTuningEnabled else {
            return ZenithPerformanceProfile.current.developFullMaxDimension
        }
        let d = UserDefaults.standard.double(forKey: ZenithPerformanceCustomTuning.fullMaxKey)
        let fallback = Double(ZenithPerformanceProfile.current.developFullMaxDimension)
        let v = d > 0 ? d : fallback
        return CGFloat(min(max(v, 1_024), 8_192))
    }

    nonisolated static var developSourceCacheCapacity: Int {
        guard isCustomTuningEnabled else {
            return ZenithPerformanceProfile.current.developSourceCacheCapacity
        }
        let raw = UserDefaults.standard.integer(forKey: ZenithPerformanceCustomTuning.sourceCapacityKey)
        let fallback = ZenithPerformanceProfile.current.developSourceCacheCapacity
        let v = raw > 0 ? raw : fallback
        return min(max(v, 1), 12)
    }

    nonisolated static var thumbnailCacheCountLimit: Int {
        guard isCustomTuningEnabled else {
            return ZenithPerformanceProfile.current.thumbnailCacheCountLimit
        }
        let raw = UserDefaults.standard.integer(forKey: ZenithPerformanceCustomTuning.thumbnailCountKey)
        let fallback = ZenithPerformanceProfile.current.thumbnailCacheCountLimit
        let v = raw > 0 ? raw : fallback
        return min(max(v, 200), 6_000)
    }

    nonisolated static var thumbnailCacheCostLimitBytes: Int {
        guard isCustomTuningEnabled else {
            return ZenithPerformanceProfile.current.thumbnailCacheCostLimitBytes
        }
        let mb = UserDefaults.standard.integer(forKey: ZenithPerformanceCustomTuning.thumbnailCostMBKey)
        let fallbackMB = max(32, ZenithPerformanceProfile.current.thumbnailCacheCostLimitBytes / (1024 * 1024))
        let v = mb > 0 ? mb : fallbackMB
        let clampedMB = min(max(v, 32), 512)
        return clampedMB * 1024 * 1024
    }
}

/// Intervalle d’auto-sauvegarde du catalogue (secondes). Valeurs discrètes persistées en `UserDefaults`.
nonisolated enum ZenithCatalogAutosaveInterval: Int, CaseIterable, Identifiable, Sendable {
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case tenMinutes = 600

    var id: Int { rawValue }

    static let userDefaultsKey = "zenith.catalogAutosaveIntervalSeconds"

    nonisolated static var current: ZenithCatalogAutosaveInterval {
        get {
            let v = UserDefaults.standard.integer(forKey: userDefaultsKey)
            return Self(rawValue: v) ?? .oneMinute
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey)
        }
    }

    var labelKey: String {
        switch self {
        case .oneMinute: "settings.catalog.autosave.1m"
        case .twoMinutes: "settings.catalog.autosave.2m"
        case .fiveMinutes: "settings.catalog.autosave.5m"
        case .tenMinutes: "settings.catalog.autosave.10m"
        }
    }
}

// MARK: - Couleur (aperçu Develop)

/// Profil RVB utilisé pour interpréter les fichiers **sans** ICC embarqué.
nonisolated enum ZenithAssumedRGBProfile: String, CaseIterable, Identifiable, Hashable, Sendable {
    case sRGB
    case adobeRGB1998
    case rommRGB

    var id: String { rawValue }

    static let userDefaultsKey = "zenith.assumedRGBProfileForUntagged"

    nonisolated static var current: ZenithAssumedRGBProfile {
        get {
            let raw = UserDefaults.standard.string(forKey: userDefaultsKey) ?? ""
            return Self(rawValue: raw) ?? .sRGB
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey)
        }
    }

    nonisolated var cgColorSpace: CGColorSpace {
        switch self {
        case .sRGB:
            return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        case .adobeRGB1998:
            return CGColorSpace(name: CGColorSpace.adobeRGB1998)
                ?? CGColorSpace(name: CGColorSpace.sRGB)
                ?? CGColorSpaceCreateDeviceRGB()
        case .rommRGB:
            return CGColorSpace(name: CGColorSpace.rommrgb)
                ?? CGColorSpace(name: CGColorSpace.sRGB)
                ?? CGColorSpaceCreateDeviceRGB()
        }
    }

    var settingsLabelKey: String {
        switch self {
        case .sRGB: "settings.color.assumed.srgb"
        case .adobeRGB1998: "settings.color.assumed.adobe"
        case .rommRGB: "settings.color.assumed.prophoto"
        }
    }

    var localizedLabel: String {
        String(localized: String.LocalizationValue(settingsLabelKey))
    }
}

nonisolated enum ZenithColorPreferences: Sendable {
    static let useDisplayP3OutputKey = "zenith.displayP3PreviewOutput"
    static let cmykSoftProofEnabledKey = "zenith.cmykSoftProofEnabled"

    nonisolated static var useDisplayP3PreviewOutput: Bool {
        get { UserDefaults.standard.bool(forKey: useDisplayP3OutputKey) }
        set { UserDefaults.standard.set(newValue, forKey: useDisplayP3OutputKey) }
    }

    nonisolated static var cmykSoftProofEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: cmykSoftProofEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: cmykSoftProofEnabledKey) }
    }

    /// Inclure dans la clé du cache source Develop / miniatures développées pour refléter les changements de politique couleur.
    nonisolated static var developSourceCachePolicyHash: Int {
        var h = Hasher()
        h.combine(ZenithAssumedRGBProfile.current.rawValue)
        h.combine(useDisplayP3PreviewOutput)
        h.combine(cmykSoftProofEnabled)
        return h.finalize()
    }
}
