//
//  DevelopCurveEditor.swift
//  Zenith
//

import SwiftUI

/// Éditeur 2D de courbe tonalité (entrée → sortie normalisées [0, 1]).
struct DevelopCurveEditor: View {
    @Binding var curve: ToneCurve

    private let pad: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button(String(localized: "develop.curve.add_point")) {
                    insertMidPointInLargestGap()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
                .foregroundStyle(ZenithTheme.adjustmentOrange)

                Button(String(localized: "develop.curve.reset")) {
                    curve = .identity
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }

            GeometryReader { geo in
                let w = max(1, geo.size.width - pad * 2)
                let h = max(1, geo.size.height - pad * 2)
                let pts = curve.normalized().points
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.35))

                    Path { p in
                        p.move(to: CGPoint(x: pad, y: pad + h))
                        p.addLine(to: CGPoint(x: pad + w, y: pad))
                    }
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)

                    let sampled = ToneCurveInterpolation.sampleMonotoneYC(curve.normalized(), sampleCount: 96)
                    Path { path in
                        guard sampled.count >= 2 else { return }
                        for (i, yv) in sampled.enumerated() {
                            let xn = Double(i) / Double(sampled.count - 1)
                            let pt = CGPoint(
                                x: pad + CGFloat(xn) * w,
                                y: pad + CGFloat(1 - yv) * h
                            )
                            if i == 0 {
                                path.move(to: pt)
                            } else {
                                path.addLine(to: pt)
                            }
                        }
                    }
                    .stroke(ZenithTheme.adjustmentOrange, lineWidth: 2)

                    ForEach(pts.indices, id: \.self) { index in
                        let pt = pts[index]
                        let cx = pad + CGFloat(pt.x) * w
                        let cy = pad + CGFloat(1 - pt.y) * h
                        Circle()
                            .fill(knobFill(index: index, count: pts.count))
                            .frame(width: knobSize(index: index, count: pts.count), height: knobSize(index: index, count: pts.count))
                            .position(x: cx, y: cy)
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { g in
                                        let nx = Double((g.location.x - pad) / w)
                                        let ny = 1 - Double((g.location.y - pad) / h)
                                        applyDrag(index: index, nx: nx, ny: ny, pointCount: pts.count)
                                    }
                            )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 140)

            Text("develop.curve.hint")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func knobSize(index: Int, count: Int) -> CGFloat {
        (index == 0 || index == count - 1) ? 9 : 11
    }

    private func knobFill(index: Int, count: Int) -> Color {
        if index == 0 || index == count - 1 {
            return Color.white.opacity(0.8)
        }
        return ZenithTheme.adjustmentOrange
    }

    private func applyDrag(index: Int, nx: Double, ny: Double, pointCount: Int) {
        var n = curve.normalized().points
        guard index < n.count, pointCount == n.count else { return }
        if index == 0 {
            n[0] = ToneCurvePoint(x: 0, y: 0)
        } else if index == n.count - 1 {
            n[n.count - 1] = ToneCurvePoint(x: 1, y: 1)
        } else {
            let minX = n[index - 1].x + 1e-4
            let maxX = n[index + 1].x - 1e-4
            let minY = n[index - 1].y
            let maxY = n[index + 1].y
            n[index].x = min(maxX, max(minX, nx))
            let clampedY = min(1, max(0, ny))
            n[index].y = min(maxY, max(minY, clampedY))
        }
        curve = ToneCurve(points: n).normalized()
    }

    private func insertMidPointInLargestGap() {
        let base = curve.normalized().points
        guard base.count >= 2 else { return }
        var bestI = 0
        var bestGap = 0.0
        for i in 0 ..< base.count - 1 {
            let g = base[i + 1].x - base[i].x
            if g > bestGap {
                bestGap = g
                bestI = i
            }
        }
        guard bestGap > 0.06 else { return }
        let midX = (base[bestI].x + base[bestI + 1].x) / 2
        let midY = (base[bestI].y + base[bestI + 1].y) / 2
        var next = base
        next.insert(ToneCurvePoint(x: midX, y: midY), at: bestI + 1)
        curve = ToneCurve(points: next).normalized()
    }
}
