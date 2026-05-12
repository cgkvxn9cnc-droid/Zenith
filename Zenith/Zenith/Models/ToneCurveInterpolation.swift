//
//  ToneCurveInterpolation.swift
//  Zenith
//
//  Interpolation cubique monotone (PCHIP / Fritsch–Carlson) pour échantillonner les courbes
//  utilisateur en LUT sans créer de sur-oscillations.
//

import Foundation

/// Pure calcul numérique ; isolé sur aucun acteur (appelable depuis le pipeline Core Image hors MainActor).
nonisolated enum ToneCurveInterpolation {
    /// Échantillonne la courbe en `sampleCount` valeurs `y` pour `x ∈ [0,1]` uniformes.
    static func sampleMonotoneYC(_ curve: ToneCurve, sampleCount: Int) -> [Double] {
        let n = max(4, sampleCount)
        let c = curve.normalized()
        let pts = c.points
        guard pts.count >= 2 else {
            return (0 ..< n).map { Double($0) / Double(n - 1) }
        }
        let xs = pts.map(\.x)
        let ys = pts.map(\.y)
        let tangents = pchipSlopes(x: xs, y: ys)
        var out: [Double] = []
        out.reserveCapacity(n)
        for j in 0 ..< n {
            let xq = Double(j) / Double(n - 1)
            let yv = evaluateHermite(x: xs, y: ys, m: tangents, xq: xq)
            out.append(min(1, max(0, yv)))
        }
        return out
    }

    // MARK: - PCHIP slopes (extrémités adaptées type SciPy)

    private static func pchipSlopes(x: [Double], y: [Double]) -> [Double] {
        precondition(x.count == y.count && x.count >= 2)
        let n = x.count
        var hk = [Double](repeating: 0, count: n - 1)
        var dk = [Double](repeating: 0, count: n - 1)
        for i in 0 ..< n - 1 {
            hk[i] = x[i + 1] - x[i]
            dk[i] = hk[i] > 0 ? (y[i + 1] - y[i]) / hk[i] : 0
        }
        var m = [Double](repeating: 0, count: n)
        if n == 2 {
            m[0] = dk[0]
            m[1] = dk[0]
            return m
        }
        m[0] = dThreePoint(x0: x[0], x1: x[1], x2: x[2], f0: y[0], f1: y[1], f2: y[2], edge0: true)
        for k in 1 ..< n - 1 {
            let smk0 = dk[k - 1]
            let smk1 = dk[k]
            if smk0 == 0 || smk1 == 0 || smk0.sign != smk1.sign {
                m[k] = 0
            } else {
                let w1 = 2 * hk[k] + hk[k - 1]
                let w2 = hk[k] + 2 * hk[k - 1]
                m[k] = (w1 + w2) / (w1 / smk0 + w2 / smk1)
            }
        }
        m[n - 1] = dThreePoint(
            x0: x[n - 3], x1: x[n - 2], x2: x[n - 1],
            f0: y[n - 3], f1: y[n - 2], f2: y[n - 1], edge0: false
        )
        return m
    }

    private static func dThreePoint(
        x0: Double, x1: Double, x2: Double,
        f0: Double, f1: Double, f2: Double,
        edge0: Bool
    ) -> Double {
        let h0 = x1 - x0
        let h1 = x2 - x1
        guard h0 > 0, h1 > 0 else { return 0 }
        let d0 = (f1 - f0) / h0
        let d1 = (f2 - f1) / h1
        if d0 == 0 || d1 == 0 || d0.sign != d1.sign { return 0 }
        let w = edge0 ? 2 * h1 + h0 : h1 + 2 * h0
        let w1 = edge0 ? h0 + 2 * h1 : 2 * h0 + h1
        return (w + w1) / (w / d0 + w1 / d1)
    }

    private static func evaluateHermite(x: [Double], y: [Double], m: [Double], xq: Double) -> Double {
        if xq <= x.first! { return y.first! }
        if xq >= x.last! { return y.last! }
        var k = 0
        for i in 0 ..< x.count - 1 {
            if xq >= x[i] && xq <= x[i + 1] {
                k = i
                break
            }
        }
        let h = x[k + 1] - x[k]
        guard h > 0 else { return y[k] }
        let t = (xq - x[k]) / h
        let t2 = t * t
        let t3 = t2 * t
        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2
        return h00 * y[k] + h10 * h * m[k] + h01 * y[k + 1] + h11 * h * m[k + 1]
    }
}
