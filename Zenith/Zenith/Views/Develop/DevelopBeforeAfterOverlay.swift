//
//  DevelopBeforeAfterOverlay.swift
//  Zenith
//

import AppKit
import SwiftUI

/// Split-screen avant/après avec curseur vertical glissant.
/// À gauche du curseur : image originale ; à droite : image développée.
struct DevelopBeforeAfterOverlay: View {
    let originalImage: NSImage
    let developedImage: NSImage

    @State private var splitFraction: CGFloat = 0.5
    /// Ancre au début du geste : sans cela `DragGesture.location` (relatif à la poignée étroite) fausse le ratio.
    @State private var splitDragAnchorFraction: CGFloat?

    private let handleWidth: CGFloat = 3
    private let handleHitWidth: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let splitX = w * splitFraction

            ZStack {
                developedSide(in: geo.size)
                originalSide(in: geo.size, splitX: splitX)
                dividerLine(splitX: splitX, height: h)
                labels(splitX: splitX, height: h, totalWidth: w)
                dragSeparator(splitX: splitX, height: h)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if splitDragAnchorFraction == nil {
                            splitDragAnchorFraction = splitFraction
                        }
                        guard let start = splitDragAnchorFraction, w > 1 else { return }
                        let next = start + value.translation.width / w
                        splitFraction = max(0.05, min(0.95, next))
                    }
                    .onEnded { _ in
                        splitDragAnchorFraction = nil
                    }
            )
        }
        .clipped()
    }

    // MARK: - Sub-views

    private func developedSide(in size: CGSize) -> some View {
        Image(nsImage: developedImage)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size.width, height: size.height)
    }

    private func originalSide(in size: CGSize, splitX: CGFloat) -> some View {
        Image(nsImage: originalImage)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size.width, height: size.height)
            .clipShape(
                HorizontalClipShape(maxX: splitX)
            )
    }

    private func dividerLine(splitX: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(Color.white)
            .frame(width: handleWidth, height: height)
            .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 0)
            .position(x: splitX, y: height / 2)
            .allowsHitTesting(false)
    }

    private func labels(splitX: CGFloat, height: CGFloat, totalWidth: CGFloat) -> some View {
        ZStack {
            Text("develop.compare.before")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.55)))
                .position(
                    x: max(40, splitX / 2),
                    y: height - 24
                )

            Text("develop.compare.after")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.55)))
                .position(
                    x: min(splitX + (totalWidth - splitX) / 2, totalWidth - 40),
                    y: height - 24
                )
        }
        .allowsHitTesting(false)
    }

    /// Ligne du curseur (la zone active de glissement est toute la surface via `DragGesture` sur le `ZStack`).
    private func dragSeparator(splitX: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.001))
            .frame(width: handleHitWidth, height: height)
            .position(x: splitX, y: height / 2)
            .allowsHitTesting(false)
    }
}

/// Masque de clip qui ne montre que les pixels à gauche de `maxX`.
private struct HorizontalClipShape: Shape {
    var maxX: CGFloat

    var animatableData: CGFloat {
        get { maxX }
        set { maxX = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY, width: maxX, height: rect.height))
    }
}
