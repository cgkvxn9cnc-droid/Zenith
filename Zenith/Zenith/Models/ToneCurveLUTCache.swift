//
//  ToneCurveLUTCache.swift
//  Zenith
//

import Foundation

/// Cache LRU simple des LUT PCHIP pour les quatre courbes (évite recomput lors des redraws Identiques).
nonisolated enum ToneCurveLUTCache {
    struct CurveLUTBundle: Sendable {
        /// `nil` = courbe maître neutre au sens `isEffectivelyIdentity`.
        let master: [Double]?
        /// `nil` = identité canal.
        let red: [Double]?
        let green: [Double]?
        let blue: [Double]?
    }

    private struct Key: Hashable, Sendable {
        let mh: UInt64
        let rh: UInt64
        let gh: UInt64
        let bh: UInt64
        let sampleCount: Int
    }

    private final class Entry {
        let bundle: CurveLUTBundle
        init(_ bundle: CurveLUTBundle) { self.bundle = bundle }
    }

    private static let lock = NSLock()
    private static var orderedKeys: [Key] = []
    private static var storage: [Key: Entry] = [:]
    private static let maxEntries = 48

    static func lutBundle(
        master: ToneCurve,
        red: ToneCurve,
        green: ToneCurve,
        blue: ToneCurve,
        sampleCount: Int
    ) -> CurveLUTBundle {
        let n = sampleCount
        let km = master.stableLUTCacheHash()
        let kr = red.stableLUTCacheHash()
        let kg = green.stableLUTCacheHash()
        let kb = blue.stableLUTCacheHash()
        let key = Key(mh: km, rh: kr, gh: kg, bh: kb, sampleCount: n)

        lock.lock()
        if let existing = storage[key] {
            if let idx = orderedKeys.firstIndex(of: key) {
                orderedKeys.remove(at: idx)
            }
            orderedKeys.insert(key, at: 0)
            lock.unlock()
            return existing.bundle
        }
        lock.unlock()

        let sampledMaster: [Double]? = {
            guard !master.isEffectivelyIdentity() else { return nil }
            return ToneCurveInterpolation.sampleMonotoneYC(master.normalized(), sampleCount: n)
        }()
        let sampledRed: [Double]? = {
            guard !red.isEffectivelyIdentity() else { return nil }
            return ToneCurveInterpolation.sampleMonotoneYC(red.normalized(), sampleCount: n)
        }()
        let sampledGreen: [Double]? = {
            guard !green.isEffectivelyIdentity() else { return nil }
            return ToneCurveInterpolation.sampleMonotoneYC(green.normalized(), sampleCount: n)
        }()
        let sampledBlue: [Double]? = {
            guard !blue.isEffectivelyIdentity() else { return nil }
            return ToneCurveInterpolation.sampleMonotoneYC(blue.normalized(), sampleCount: n)
        }()

        let bundle = CurveLUTBundle(
            master: sampledMaster,
            red: sampledRed,
            green: sampledGreen,
            blue: sampledBlue
        )

        lock.lock()
        storage[key] = Entry(bundle)
        if let idx = orderedKeys.firstIndex(of: key) {
            orderedKeys.remove(at: idx)
        }
        orderedKeys.insert(key, at: 0)
        while orderedKeys.count > maxEntries {
            let dropKey = orderedKeys.removeLast()
            storage.removeValue(forKey: dropKey)
        }
        lock.unlock()

        return bundle
    }

    /// Tests / réglages — vide le cache.
    static func clearForTesting() {
        lock.lock()
        orderedKeys.removeAll(keepingCapacity: false)
        storage.removeAll(keepingCapacity: false)
        lock.unlock()
    }
}
