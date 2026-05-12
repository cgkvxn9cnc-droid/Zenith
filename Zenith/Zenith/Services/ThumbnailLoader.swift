//
//  ThumbnailLoader.swift
//  Zenith
//

@preconcurrency import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Cache mémoire partagé des miniatures : évite de redécoder l’image à chaque retour à l’écran
/// quand `LazyVGrid` / `LazyHStack` recyclent les cellules pendant le scroll.
/// Vidé automatiquement par `NSCache` en cas de pression mémoire.
nonisolated final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()

    init() {
        reapplyLimitsFromPreferences(clearEntries: false)
    }

    func reapplyLimitsFromPreferences(clearEntries: Bool) {
        cache.countLimit = ZenithEffectivePerformance.thumbnailCacheCountLimit
        cache.totalCostLimit = ZenithEffectivePerformance.thumbnailCacheCostLimitBytes
        if clearEntries {
            cache.removeAllObjects()
        }
    }

    func image(forKey key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func setImage(_ image: NSImage, forKey key: String) {
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func clear() {
        cache.removeAllObjects()
    }
}

/// Limite async globale des décodages de miniatures lancés en parallèle.
/// On évite `DispatchSemaphore.wait()` dans un contexte async : Swift 6 le signale comme erreur future.
///
/// Le throttle est annulable : si la tâche parente est annulée (cellule sortie de l’écran, scroll rapide…),
/// la file d’attente libère immédiatement le slot pour qu’une cellule visible puisse décoder à la place.
/// Cette propagation d’annulation est le levier principal de fluidité côté bibliothèque.
actor ThumbnailDecodeThrottle {
    /// 2 décodages RAW en parallèle : RawCamera utilise des files série internes ; au-delà de 2 threads
    /// on observe un deadlock sur `_dispatch_sync_f_slow` au démarrage qui empêche le commit de la
    /// fenêtre principale. 2 reste un bon compromis fluidité/sûreté sur Apple Silicon.
    static let shared = ThumbnailDecodeThrottle(limit: 2)

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private let limit: Int
    private var available: Int
    private var waiters: [Waiter] = []

    init(limit: Int) {
        self.limit = limit
        self.available = limit
    }

    func acquire() async throws {
        try Task.checkCancellation()
        if available > 0 {
            available -= 1
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                waiters.append(Waiter(id: id, continuation: cont))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    func release() {
        if waiters.isEmpty {
            available = min(limit, available + 1)
        } else {
            let waiter = waiters.removeFirst()
            waiter.continuation.resume()
        }
    }

    /// Retire un attendant annulé de la file et résout sa continuation par CancellationError,
    /// afin que `acquire()` lève proprement et que l’appelant n’occupe pas le slot.
    private func cancelWaiter(id: UUID) {
        guard let idx = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: idx)
        waiter.continuation.resume(throwing: CancellationError())
    }
}

/// Boîte explicitement `Sendable` pour transporter une `NSImage` produite dans un `Task.detached`.
/// `NSImage` n'est pas déclarée Sendable par AppKit, mais ici l'image est créée puis seulement lue par SwiftUI.
nonisolated final class ThumbnailDecodeResult: @unchecked Sendable {
    let image: NSImage?

    init(_ image: NSImage?) {
        self.image = image
    }
}

nonisolated enum ThumbnailLoader {
    /// CIContext **dédié** pour le rendu des miniatures « développées ».
    ///
    /// On évite délibérément de partager le contexte Metal de `DevelopPreviewRenderer` :
    /// au démarrage, plusieurs cellules peuvent décoder un RAW en parallèle via `CGImageSourceCreateThumbnailAtIndex`,
    /// qui réutilise en interne un `CIContext` derrière `RawCamera-Provider-Render-Queue`.
    /// Mélanger ces décodes avec le contexte Metal du Develop produit un deadlock
    /// (`GetSurfaceFromCacheAndFill` → `_dispatch_sync_f_slow`) qui peut empêcher
    /// le main thread de commiter la première fenêtre.
    /// Un contexte indépendant utilisant les valeurs par défaut isole proprement les deux pipelines.
    private static let developedThumbnailContext: CIContext = CIContext(options: [
        .useSoftwareRenderer: NSNumber(value: false),
        .cacheIntermediates: NSNumber(value: false)
    ])

    /// Construit une clé de cache stable à partir des paramètres uniques d’une miniature
    /// (chemin du fichier, taille cible, hash des réglages développement le cas échéant).
    static func cacheKey(url: URL, maxPixel: CGFloat, developHash: Int? = nil) -> String {
        let bucket = Int(maxPixel.rounded())
        if let developHash {
            return "\(url.path)|\(bucket)|d\(developHash)|c\(ZenithColorPreferences.developSourceCachePolicyHash)"
        } else {
            return "\(url.path)|\(bucket)"
        }
    }

    static func thumbnail(for url: URL, maxPixel: CGFloat = 320) -> NSImage? {
        let key = cacheKey(url: url, maxPixel: maxPixel)
        if let cached = ThumbnailCache.shared.image(forKey: key) {
            return cached
        }

        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel)
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            return NSImage(contentsOf: url)
        }
        let size = NSSize(width: cg.width, height: cg.height)
        let img = NSImage(cgImage: cg, size: size)
        ThumbnailCache.shared.setImage(img, forKey: key)
        return img
    }

    /// Renvoie une miniature qui reflète les `DevelopSettings` de la photo (aperçu cohérent dans la grille / pellicule).
    /// Si les réglages sont neutres, retombe sur le chemin rapide (thumbnail brut sans pipeline Core Image).
    /// `cacheHash` permet d’invalider proprement la miniature dès que les réglages changent (typiquement
    /// `photo.developBlob.hashValue`, calculé une seule fois côté cellule).
    static func developedThumbnail(for url: URL, settings: DevelopSettings, cacheHash: Int = 0, maxPixel: CGFloat = 320) -> NSImage? {
        if settings == .neutral {
            return thumbnail(for: url, maxPixel: maxPixel)
        }

        let key = cacheKey(url: url, maxPixel: maxPixel, developHash: cacheHash)
        if let cached = ThumbnailCache.shared.image(forKey: key) {
            return cached
        }

        if let ciRaw = ZenithImageSourceLoader.ciImage(
            contentsOf: url,
            maxPixelDimension: maxPixel,
            draftMode: true
        ) {
            let ciPro = ZenithSourceColorNormalizer.normalizeForDevelopPipeline(image: ciRaw, url: url)
            if let processed = DevelopPreviewRenderer.developedCIImage(from: ciPro, settings: settings, quality: .fast),
               let ir = DevelopPreviewRenderer.integralRectForRasterization(processed.extent),
               ir.width > 0, ir.height > 0,
               let cgOut = ZenithColorRendering.createDevelopPreviewCGImage(
                context: developedThumbnailContext,
                output: processed,
                from: ir
               ) {
            let img = NSImage(cgImage: cgOut, size: NSSize(width: CGFloat(cgOut.width), height: CGFloat(cgOut.height)))
            ThumbnailCache.shared.setImage(img, forKey: key)
            return img
            }
        }

        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel)
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            return thumbnail(for: url, maxPixel: maxPixel)
        }

        let baseSize = NSSize(width: cg.width, height: cg.height)
        let baseImage = NSImage(cgImage: cg, size: baseSize)
        let ciRaw = CIImage(cgImage: cg)
        let ci = ZenithSourceColorNormalizer.normalizeForDevelopPipeline(image: ciRaw, url: url)

        guard let processed = DevelopPreviewRenderer.developedCIImage(from: ci, settings: settings, quality: .fast) else {
            ThumbnailCache.shared.setImage(baseImage, forKey: key)
            return baseImage
        }
        guard let ir = DevelopPreviewRenderer.integralRectForRasterization(processed.extent) else {
            ThumbnailCache.shared.setImage(baseImage, forKey: key)
            return baseImage
        }
        guard ir.width > 0, ir.height > 0,
              let cgOut = ZenithColorRendering.createDevelopPreviewCGImage(
                context: developedThumbnailContext,
                output: processed,
                from: ir
              ) else {
            ThumbnailCache.shared.setImage(baseImage, forKey: key)
            return baseImage
        }
        let img = NSImage(cgImage: cgOut, size: NSSize(width: CGFloat(cgOut.width), height: CGFloat(cgOut.height)))
        ThumbnailCache.shared.setImage(img, forKey: key)
        return img
    }

    static func pixelSize(of url: URL) -> (Int, Int) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int
        else {
            return (0, 0)
        }
        return (w, h)
    }
}
