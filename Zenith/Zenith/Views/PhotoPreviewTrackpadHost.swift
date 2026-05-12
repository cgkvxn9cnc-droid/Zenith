//
//  PhotoPreviewTrackpadHost.swift
//  Zenith
//

import AppKit
import SwiftUI

/// Couche transparente au-dessus de l’aperçu : pincement (zoom), défilement à deux doigts (pan), ⌘+défilement (zoom), glisser souris (pan).
struct PhotoPreviewTrackpadHost: NSViewRepresentable {
    @Binding var zoomScale: CGFloat
    @Binding var panOffset: CGSize
    var viewportSize: CGSize
    var minZoom: CGFloat
    var maxZoom: CGFloat
    /// Désactiver le pan à la souris (ex. recadrage : les glissements sont pour le cadre).
    var allowsMouseDragPan: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> PreviewTrackpadNSView {
        let v = PreviewTrackpadNSView()
        v.coordinator = context.coordinator
        return v
    }

    func updateNSView(_ nsView: PreviewTrackpadNSView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncInteractionStateFromParentIfNeeded()
        nsView.allowsMouseDragPan = allowsMouseDragPan
    }

    final class Coordinator: NSObject, NSGestureRecognizerDelegate {
        var parent: PhotoPreviewTrackpadHost
        private var interactionZoom: CGFloat?
        private var interactionPan: CGSize?
        private var interactionActive = false

        init(parent: PhotoPreviewTrackpadHost) {
            self.parent = parent
        }

        func syncInteractionStateFromParentIfNeeded() {
            guard !interactionActive else { return }
            interactionZoom = parent.zoomScale
            interactionPan = parent.panOffset
        }

        func currentZoom() -> CGFloat {
            interactionZoom ?? parent.zoomScale
        }

        func gestureRecognizer(
            _: NSGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: NSGestureRecognizer
        ) -> Bool {
            true
        }

        func applyZoom(_ z: CGFloat, anchorInNSView anchorNS: NSPoint? = nil, nativeViewportSize: CGSize? = nil) {
            let clamped = z.clamped(to: parent.minZoom ... parent.maxZoom)
            guard Thread.isMainThread else {
                DispatchQueue.main.async { [weak self] in
                    self?.applyZoom(clamped, anchorInNSView: anchorNS, nativeViewportSize: nativeViewportSize)
                }
                return
            }
            let currentZoom = interactionZoom ?? parent.zoomScale
            let currentPan = interactionPan ?? parent.panOffset
            let oldZoom = max(parent.minZoom, currentZoom)
            var nextPan = currentPan
            if let anchorNS, oldZoom > 0.000_1, abs(clamped - oldZoom) > 0.000_1 {
                let viewport = nativeViewportSize ?? parent.viewportSize
                let anchor = swiftUIPoint(fromNSPoint: anchorNS, viewportSize: viewport)
                let center = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
                let currentOffset = CGPoint(x: currentPan.width, y: currentPan.height)
                let dx = anchor.x - center.x - currentOffset.x
                let dy = anchor.y - center.y - currentOffset.y
                let ratio = clamped / oldZoom
                let nextOffset = CGPoint(
                    x: anchor.x - center.x - dx * ratio,
                    y: anchor.y - center.y - dy * ratio
                )
                nextPan = CGSize(width: nextOffset.x, height: nextOffset.y)
            }
            interactionZoom = clamped
            interactionPan = nextPan
            parent.panOffset = nextPan
            parent.zoomScale = clamped
        }

        func beginInteraction() {
            interactionActive = true
            if interactionZoom == nil { interactionZoom = parent.zoomScale }
            if interactionPan == nil { interactionPan = parent.panOffset }
        }

        func endInteraction() {
            interactionActive = false
            interactionZoom = parent.zoomScale
            interactionPan = parent.panOffset
        }

        func applyScrollPan(dx: CGFloat, dy: CGFloat) {
            let s: CGFloat = 0.45
            guard Thread.isMainThread else {
                DispatchQueue.main.async { [weak self] in
                    self?.applyScrollPan(dx: dx, dy: dy)
                }
                return
            }
            let currentPan = interactionPan ?? parent.panOffset
            let nextPan = CGSize(
                width: currentPan.width - dx * s,
                height: currentPan.height - dy * s
            )
            interactionPan = nextPan
            parent.panOffset = nextPan
        }

        /// `dx`/`dy` proviennent de `locationInWindow` (NSView non flipped : Y croît vers le haut).
        /// SwiftUI `.offset` utilise Y vers le bas : on inverse `dy` pour que l’image suive directement le curseur.
        func applyMouseDragPan(dx: CGFloat, dy: CGFloat) {
            guard Thread.isMainThread else {
                DispatchQueue.main.async { [weak self] in
                    self?.applyMouseDragPan(dx: dx, dy: dy)
                }
                return
            }
            let currentPan = interactionPan ?? parent.panOffset
            let nextPan = CGSize(
                width: currentPan.width + dx,
                height: currentPan.height - dy
            )
            interactionPan = nextPan
            parent.panOffset = nextPan
        }

        func applyCommandScrollZoom(deltaY: CGFloat) {
            let f = exp(deltaY * 0.004)
            let next = (parent.zoomScale * f).clamped(to: parent.minZoom ... parent.maxZoom)
            applyZoom(next)
        }

        func applyCommandScrollZoom(deltaY: CGFloat, cursorInNSView: NSPoint, nativeViewportSize: CGSize) {
            let f = exp(deltaY * 0.004)
            let next = (parent.zoomScale * f).clamped(to: parent.minZoom ... parent.maxZoom)
            applyZoom(next, anchorInNSView: cursorInNSView, nativeViewportSize: nativeViewportSize)
        }

        /// Convertit les coordonnées AppKit (origine bas-gauche) en coordonnées SwiftUI (origine haut-gauche).
        private func swiftUIPoint(fromNSPoint point: NSPoint, viewportSize: CGSize) -> CGPoint {
            CGPoint(x: point.x, y: viewportSize.height - point.y)
        }
    }

    final class PreviewTrackpadNSView: NSView {
        weak var coordinator: Coordinator?
        private var dragPanning = false
        /// Dernière position du curseur en coordonnées de la fenêtre (Y vers le haut, NSView non flipped).
        private var lastDragLocation: NSPoint?
        /// Synchronisé depuis SwiftUI dans `updateNSView`.
        var allowsMouseDragPan = true

        override var isOpaque: Bool { false }

        override func resetCursorRects() {
            super.resetCursorRects()
            if allowsMouseDragPan {
                addCursorRect(bounds, cursor: .openHand)
            }
        }

        override func scrollWheel(with event: NSEvent) {
            guard let coordinator else {
                super.scrollWheel(with: event)
                return
            }
            guard event.hasPreciseScrollingDeltas else {
                super.scrollWheel(with: event)
                return
            }
            if event.modifierFlags.contains(.command) {
                coordinator.beginInteraction()
                let local = preferredAnchorPoint(from: event)
                coordinator.applyCommandScrollZoom(
                    deltaY: event.scrollingDeltaY,
                    cursorInNSView: local,
                    nativeViewportSize: bounds.size
                )
                if event.phase == .ended || event.phase == .cancelled || event.phase == .mayBegin {
                    coordinator.endInteraction()
                }
                return
            }
            coordinator.applyScrollPan(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
        }

        /// Gestes trackpad natifs (pinch to zoom).
        override func magnify(with event: NSEvent) {
            guard let coordinator else {
                super.magnify(with: event)
                return
            }
            let m = event.magnification
            guard abs(m) > 0.000_01 else { return }
            coordinator.beginInteraction()
            let baseZoom = coordinator.currentZoom()
            let next = (baseZoom * (1.0 + m))
                .clamped(to: coordinator.parent.minZoom ... coordinator.parent.maxZoom)
            let local = preferredAnchorPoint(from: event)
            coordinator.applyZoom(next, anchorInNSView: local, nativeViewportSize: bounds.size)
            if event.phase == .ended || event.phase == .cancelled {
                coordinator.endInteraction()
            }
        }

        override func mouseDown(with event: NSEvent) {
            guard allowsMouseDragPan else {
                super.mouseDown(with: event)
                return
            }
            if event.buttonNumber == 0 {
                coordinator?.beginInteraction()
                dragPanning = true
                lastDragLocation = event.locationInWindow
                NSCursor.closedHand.push()
            } else {
                super.mouseDown(with: event)
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard allowsMouseDragPan else {
                super.mouseDragged(with: event)
                return
            }
            guard dragPanning, event.buttonNumber == 0 else {
                super.mouseDragged(with: event)
                return
            }
            let current = event.locationInWindow
            let dx = current.x - (lastDragLocation?.x ?? current.x)
            let dy = current.y - (lastDragLocation?.y ?? current.y)
            lastDragLocation = current
            coordinator?.applyMouseDragPan(dx: dx, dy: dy)
        }

        override func mouseUp(with event: NSEvent) {
            if event.buttonNumber == 0 {
                if dragPanning {
                    NSCursor.pop()
                }
                dragPanning = false
                lastDragLocation = nil
                coordinator?.endInteraction()
            }
            super.mouseUp(with: event)
        }

        /// Point d’ancrage robuste pour le zoom trackpad : préfère la position souris réelle de la fenêtre.
        private func preferredAnchorPoint(from event: NSEvent) -> NSPoint {
            if let window {
                let mouseInWindow = window.mouseLocationOutsideOfEventStream
                let p = convert(mouseInWindow, from: nil)
                if bounds.contains(p) {
                    return p
                }
            }
            let fallback = convert(event.locationInWindow, from: nil)
            if bounds.contains(fallback) {
                return fallback
            }
            return NSPoint(x: bounds.midX, y: bounds.midY)
        }
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
