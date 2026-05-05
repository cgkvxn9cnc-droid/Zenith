//
//  DevelopPreviewToolOverlay.swift
//  Zenith
//

import SwiftUI

/// Retouche locale : tap sur l’image pour adoucir une zone.
struct DevelopPreviewToolOverlay: View {
    let viewportSize: CGSize
    let imageRect: CGRect
    /// Coordonnées normalisées dans l’image (0…1), origine haut-gauche.
    var onHealAtNormalized: ((CGFloat, CGFloat) -> Void)?

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            let p = value.location
                            guard imageRect.width > 2, imageRect.height > 2, imageRect.contains(p) else { return }
                            let nx = (p.x - imageRect.minX) / imageRect.width
                            let ny = (p.y - imageRect.minY) / imageRect.height
                            onHealAtNormalized?(nx, ny)
                        }
                )

            Text("develop.tool.heal.hint")
                .font(.caption)
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.top, 16)
                .allowsHitTesting(false)
        }
        .frame(width: viewportSize.width, height: viewportSize.height)
    }
}
