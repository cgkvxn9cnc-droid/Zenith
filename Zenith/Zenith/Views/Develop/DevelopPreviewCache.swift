//
//  DevelopPreviewCache.swift
//  Zenith
//

import AppKit
import CoreImage
import Foundation

/// Cache de rendu intermédiaire pour le pipeline Develop.
///
/// Inspirations darktable :
/// - **Pipeline cache** ("pixelpipe cache" dans darktable) : darktable garde un cache de buffers
///   intermédiaires pour ne pas re-recalculer toutes les iop quand on bouge un seul curseur.
///   Ici on garde au minimum la **CIImage source** (résultat du décodage RAW + scale to display)
///   en cache LRU par URL : c'est l'étape la plus coûteuse, et la plus stable d'un curseur à l'autre.
/// - **Proxy / "preview" pipe** : darktable a deux pipes, "full" et "preview" (basse résolution rapide).
///   Pendant un drag de curseur, on bascule sur le proxy ; à la sortie du drag on rebascule sur le full.
///   Les dimensions et la profondeur du LRU suivent `ZenithEffectivePerformance` (Réglages Zenith).
final class DevelopPreviewCache: @unchecked Sendable {
    static let shared = DevelopPreviewCache()

    private var proxyMaxDimension: CGFloat { ZenithEffectivePerformance.developProxyMaxDimension }
    private var fullMaxDimension: CGFloat { ZenithEffectivePerformance.developFullMaxDimension }
    private var sourceCacheCapacity: Int { ZenithEffectivePerformance.developSourceCacheCapacity }

    private let lock = NSLock()
    /// `CIContext` Metal (`DevelopPreviewRenderer.sharedContext`) n’est pas utilisable en parallèle depuis plusieurs threads :
    /// des `Task.detached` qui se chevauchent (aperçu + proxy) provoquaient des `EXC_BAD_ACCESS`.
    private let pipelineLock = NSLock()

    private struct CachedSource {
        let url: URL
        let maxDim: CGFloat
        /// Aligné sur `ZenithImageSourceLoader` : le décodage RAW « draft » ne doit pas servir de source au rendu plein qualité.
        let draftDecoding: Bool
        /// Politique couleur (`ZenithColorPreferences`) : invalide le LRU si l’utilisateur change le profil assumé ou la sortie P3.
        let colorPolicyHash: Int
        let image: CIImage
    }

    /// LRU implémenté sur un simple tableau (profondeur selon le profil performance → coût O(N) négligeable).
    /// L'élément en tête du tableau est le plus récemment utilisé.
    private var sourceCache: [CachedSource] = []

    /// Dernier rendu plein-cadre cohérent (URL + settings) ; permet d'éviter le pipeline complet
    /// quand on revient sur exactement les mêmes paramètres (par ex. après un toggle compare).
    private var cachedFullURL: URL?
    private var cachedFullSettings: DevelopSettings?
    private var cachedFullImage: NSImage?
    private var cachedProxyURL: URL?
    private var cachedProxySettings: DevelopSettings?
    private var cachedProxyImage: NSImage?

    /// Reuse du contexte Metal global : un seul context partagé pour tout l'app, ce qui maximise
    /// le hit rate des caches MPS et évite la pression VRAM.
    private var context: CIContext { DevelopPreviewRenderer.sharedContext }

    // MARK: - Public API

    struct RenderRequest: Sendable {
        let url: URL
        let settings: DevelopSettings
        let applyCrop: Bool
        let proxyOnly: Bool
    }

    struct RenderResult: Sendable {
        let image: NSImage?
        let isProxy: Bool
    }

    /// Rendu principal. Si `proxyOnly`, retourne une version basse-res rapide.
    func render(_ request: RenderRequest) -> RenderResult {
        if request.proxyOnly {
            return renderProxy(request)
        }
        return renderFull(request)
    }

    /// Invalide tout (changement de photo).
    func invalidate() {
        lock.lock()
        sourceCache.removeAll(keepingCapacity: true)
        cachedFullURL = nil
        cachedFullSettings = nil
        cachedFullImage = nil
        cachedProxyURL = nil
        cachedProxySettings = nil
        cachedProxyImage = nil
        lock.unlock()
    }

    /// Invalide les rendus mais conserve le cache de sources (changement de réglages uniquement).
    func invalidateResult() {
        lock.lock()
        cachedFullURL = nil
        cachedFullSettings = nil
        cachedFullImage = nil
        cachedProxyURL = nil
        cachedProxySettings = nil
        cachedProxyImage = nil
        lock.unlock()
    }

    // MARK: - Private

    private func renderProxy(_ request: RenderRequest) -> RenderResult {
        lock.lock()
        if cachedProxyURL == request.url,
           cachedProxySettings == request.settings,
           let cached = cachedProxyImage {
            lock.unlock()
            return RenderResult(image: cached, isProxy: true)
        }
        lock.unlock()

        guard let source = loadSource(url: request.url, maxDim: proxyMaxDimension, draftMode: true) else {
            return RenderResult(image: nil, isProxy: true)
        }

        guard let img = rasterizePipeline(from: source, request: request, quality: .fast) else {
            return RenderResult(image: nil, isProxy: true)
        }

        lock.lock()
        cachedProxyURL = request.url
        cachedProxySettings = request.settings
        cachedProxyImage = img
        lock.unlock()
        return RenderResult(image: img, isProxy: true)
    }

    private func renderFull(_ request: RenderRequest) -> RenderResult {
        lock.lock()
        if cachedFullURL == request.url,
           cachedFullSettings == request.settings,
           let cached = cachedFullImage {
            lock.unlock()
            return RenderResult(image: cached, isProxy: false)
        }
        lock.unlock()

        guard let source = loadSource(url: request.url, maxDim: fullMaxDimension, draftMode: false) else {
            return RenderResult(image: nil, isProxy: false)
        }

        guard let img = rasterizePipeline(from: source, request: request, quality: .high) else {
            return RenderResult(image: nil, isProxy: false)
        }

        lock.lock()
        cachedFullURL = request.url
        cachedFullSettings = request.settings
        cachedFullImage = img
        lock.unlock()
        return RenderResult(image: img, isProxy: false)
    }

    /// Récupère la source à `maxDim` depuis le cache LRU ; charge depuis le disque si nécessaire.
    /// Le cache est partagé entre proxy et full : si on a déjà la version full en mémoire, on la
    /// réutilise pour fabriquer le proxy (un simple downsample est plus rapide qu'un re-décodage RAW).
    private func loadSource(url: URL, maxDim: CGFloat, draftMode: Bool) -> CIImage? {
        let colorHash = ZenithColorPreferences.developSourceCachePolicyHash
        lock.lock()
        // 1) Hit exact ou supérieur (on tolère 10 % au-dessus pour amortir les fluctuations de la fenêtre)
        if let idx = sourceCache.firstIndex(where: {
            $0.url == url && $0.draftDecoding == draftMode && $0.colorPolicyHash == colorHash
                && $0.maxDim >= maxDim * 0.95
        }) {
            let hit = sourceCache.remove(at: idx)
            sourceCache.insert(hit, at: 0)
            let cached = hit.image
            lock.unlock()
            // Si la version cachée est plus grande, on la réduit à la volée (Lanczos via CIAffine)
            let dim = max(cached.extent.width, cached.extent.height)
            if dim > maxDim * 1.1 {
                let s = maxDim / dim
                return cached.transformed(by: CGAffineTransform(scaleX: s, y: s))
            }
            return cached
        }
        lock.unlock()

        guard let ci = ZenithImageSourceLoader.ciImage(
            contentsOf: url,
            maxPixelDimension: maxDim,
            draftMode: draftMode
        ) else { return nil }
        var output = ZenithSourceColorNormalizer.normalizeForDevelopPipeline(image: ci, url: url)
        let dim = max(output.extent.width, output.extent.height)
        if dim > maxDim {
            let s = maxDim / dim
            output = output.transformed(by: CGAffineTransform(scaleX: s, y: s))
        }

        lock.lock()
        sourceCache.removeAll { $0.url == url }
        sourceCache.insert(
            CachedSource(
                url: url,
                maxDim: maxDim,
                draftDecoding: draftMode,
                colorPolicyHash: colorHash,
                image: output
            ),
            at: 0
        )
        if sourceCache.count > sourceCacheCapacity {
            sourceCache.removeLast(sourceCache.count - sourceCacheCapacity)
        }
        lock.unlock()
        return output
    }

    /// Pipeline complet + rasterisation : une seule section critique pour le `CIContext` partagé.
    private func rasterizePipeline(from source: CIImage, request: RenderRequest, quality: DevelopPipelineQuality) -> NSImage? {
        pipelineLock.lock()
        defer { pipelineLock.unlock() }
        guard let output = DevelopPreviewRenderer.developedCIImage(
            from: source,
            settings: request.settings,
            applyCrop: request.applyCrop,
            quality: quality
        ) else {
            return nil
        }
        guard let ir = DevelopPreviewRenderer.integralRectForRasterization(output.extent) else { return nil }
        guard let cg = ZenithColorRendering.createDevelopPreviewCGImage(context: context, output: output, from: ir)
        else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width), height: CGFloat(cg.height)))
    }
}
