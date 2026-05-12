//
//  ToneCurve.swift
//  Zenith
//

import Foundation

/// Point de courbe tonalité en entrée/sortie normalisés [0, 1] (espace linéaire de travail).
nonisolated struct ToneCurvePoint: Codable, Equatable, Hashable, Sendable {
    var x: Double
    var y: Double
}

/// Courbe 1D monotone pour réglage tonal (maître RVB ou canal isolé).
/// Ancres implicites : `(0,0)` et `(1,1)` sont toujours respectées après `normalized`.
nonisolated struct ToneCurve: Codable, Equatable, Sendable {
    /// Points triés par `x` croissant (hors ancres implicites si on choisit de tout stocker).
    var points: [ToneCurvePoint]

    init(points: [ToneCurvePoint]) {
        self.points = points
    }

    /// Courbe identité sur [0, 1].
    static let identity = ToneCurve(points: [
        ToneCurvePoint(x: 0, y: 0),
        ToneCurvePoint(x: 1, y: 1)
    ])

    /// Trie, clamp, impose les extrémités et supprime les doublons `x`.
    func normalized() -> ToneCurve {
        var sorted = points.sorted { $0.x < $1.x }
        for i in sorted.indices {
            sorted[i].x = min(1, max(0, sorted[i].x))
            sorted[i].y = min(1, max(0, sorted[i].y))
        }
        var merged: [ToneCurvePoint] = []
        for p in sorted {
            if let last = merged.last, abs(last.x - p.x) < 1e-8 {
                merged[merged.count - 1] = p
            } else {
                merged.append(p)
            }
        }
        if merged.isEmpty {
            return .identity
        }
        if merged.first!.x > 1e-6 {
            merged.insert(ToneCurvePoint(x: 0, y: 0), at: 0)
        } else {
            merged[0] = ToneCurvePoint(x: 0, y: merged[0].y)
        }
        if merged.last!.x < 1 - 1e-6 {
            merged.append(ToneCurvePoint(x: 1, y: 1))
        } else {
            merged[merged.count - 1] = ToneCurvePoint(x: 1, y: merged[merged.count - 1].y)
        }
        return ToneCurve(points: merged)
    }

    /// Vérifie si la courbe (normalisée) est proche de la diagonale identité.
    func isEffectivelyIdentity(epsilon: Double = 0.002) -> Bool {
        let n = normalized()
        for p in n.points {
            if abs(p.y - p.x) > epsilon { return false }
        }
        return true
    }

    /// Hachage stable des points normalisés pour caches LUT (quantification 1e-4).
    func stableLUTCacheHash() -> UInt64 {
        var h: UInt64 = 5381
        for p in normalized().points {
            let xq = UInt64(bitPattern: Int64((p.x * 10000.0).rounded(.toNearestOrAwayFromZero)))
            let yq = UInt64(bitPattern: Int64((p.y * 10000.0).rounded(.toNearestOrAwayFromZero)))
            h = ((h &<< 5) &+ h) &+ xq
            h = ((h &<< 5) &+ h) &+ yq
        }
        return h
    }

    // MARK: - Migration depuis les curseurs « intensité » (anciennes versions)

    /// Même famille que l’ancien `applyMasterToneCurve` (sigmoïde k = 8).
    static func legacyMaster(fromIntensityPercent intensityPercent: Double) -> ToneCurve {
        let t = max(-100.0, min(100.0, intensityPercent)) / 100.0
        guard abs(t) > 1e-5 else { return .identity }
        let s = max(-1.0, min(1.0, t))
        let k = 8.0
        let sigmoid: (Double) -> Double = { x in 1.0 / (1.0 + exp(-k * (x - 0.5))) }
        let s0 = sigmoid(0)
        let s1 = sigmoid(1)
        let span = s1 - s0
        let xs: [Double] = [0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1.0]
        let ys: [Double] = xs.map { x in
            let normalizedSig = (sigmoid(x) - s0) / span
            let mixed = x + s * (normalizedSig - x)
            return min(1.0, max(0.0, mixed))
        }
        return ToneCurve(points: zip(xs, ys).map { ToneCurvePoint(x: $0, y: $1) }).normalized()
    }

    /// Même famille que l’ancien `applyChannelCurve` (sigmoïde k = 6 sur un canal).
    static func legacyChannel(fromIntensityPercent intensityPercent: Double) -> ToneCurve {
        let t = max(-100.0, min(100.0, intensityPercent)) / 100.0
        guard abs(t) > 1e-5 else { return .identity }
        let s = max(-1.0, min(1.0, t))
        let k = 6.0
        let sigmoid: (Double) -> Double = { x in 1.0 / (1.0 + exp(-k * (x - 0.5))) }
        let s0 = sigmoid(0)
        let s1 = sigmoid(1)
        let span = s1 - s0
        let n = 9
        var pts: [ToneCurvePoint] = []
        for i in 0 ..< n {
            let x = Double(i) / Double(n - 1)
            let mixed = x + s * ((sigmoid(x) - s0) / span - x)
            let y = min(1.0, max(0.0, mixed))
            pts.append(ToneCurvePoint(x: x, y: y))
        }
        return ToneCurve(points: pts).normalized()
    }
}
