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
    var minZoom: CGFloat
    var maxZoom: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> PreviewTrackpadNSView {
        let v = PreviewTrackpadNSView()
        v.coordinator = context.coordinator
        context.coordinator.attachMagnification(to: v)
        return v
    }

    func updateNSView(_ nsView: PreviewTrackpadNSView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, NSGestureRecognizerDelegate {
        var parent: PhotoPreviewTrackpadHost
        private var magnificationRecognizer: NSMagnificationGestureRecognizer?

        init(parent: PhotoPreviewTrackpadHost) {
            self.parent = parent
        }

        func attachMagnification(to view: PreviewTrackpadNSView) {
            guard magnificationRecognizer == nil else { return }
            let g = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnification(_:)))
            g.delegate = self
            view.addGestureRecognizer(g)
            magnificationRecognizer = g
        }

        func detachMagnification(from view: PreviewTrackpadNSView) {
            if let g = magnificationRecognizer {
                view.removeGestureRecognizer(g)
                magnificationRecognizer = nil
            }
        }

        /// Le pincement envoie des incréments ; on applique puis on remet `magnification` à 0 (recommandation Apple).
        @objc func handleMagnification(_ sender: NSMagnificationGestureRecognizer) {
            switch sender.state {
            case .began:
                sender.magnification = 0
            case .changed:
                let m = sender.magnification
                guard abs(m) > 0.000_01 else { return }
                let next = (parent.zoomScale * (1.0 + m)).clamped(to: parent.minZoom ... parent.maxZoom)
                applyZoom(next)
                sender.magnification = 0
            default:
                break
            }
        }

        func gestureRecognizer(
            _: NSGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: NSGestureRecognizer
        ) -> Bool {
            true
        }

        func applyZoom(_ z: CGFloat) {
            let clamped = z.clamped(to: parent.minZoom ... parent.maxZoom)
            DispatchQueue.main.async {
                self.parent.zoomScale = clamped
            }
        }

        func applyScrollPan(dx: CGFloat, dy: CGFloat) {
            let s: CGFloat = 0.45
            DispatchQueue.main.async {
                self.parent.panOffset = CGSize(
                    width: self.parent.panOffset.width - dx * s,
                    height: self.parent.panOffset.height - dy * s
                )
            }
        }

        func applyMouseDragPan(dx: CGFloat, dy: CGFloat) {
            DispatchQueue.main.async {
                self.parent.panOffset = CGSize(
                    width: self.parent.panOffset.width + dx,
                    height: self.parent.panOffset.height - dy
                )
            }
        }

        func applyCommandScrollZoom(deltaY: CGFloat) {
            let f = exp(deltaY * 0.004)
            let next = (parent.zoomScale * f).clamped(to: parent.minZoom ... parent.maxZoom)
            applyZoom(next)
        }
    }

    final class PreviewTrackpadNSView: NSView {
        weak var coordinator: Coordinator?
        private var dragPanning = false

        override var isOpaque: Bool { false }

        override func removeFromSuperview() {
            coordinator?.detachMagnification(from: self)
            super.removeFromSuperview()
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
                coordinator.applyCommandScrollZoom(deltaY: event.scrollingDeltaY)
                return
            }
            coordinator.applyScrollPan(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
        }

        override func mouseDown(with event: NSEvent) {
            if event.buttonNumber == 0 {
                dragPanning = true
            } else {
                super.mouseDown(with: event)
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard dragPanning, event.buttonNumber == 0 else {
                super.mouseDragged(with: event)
                return
            }
            coordinator?.applyMouseDragPan(dx: event.deltaX, dy: event.deltaY)
        }

        override func mouseUp(with event: NSEvent) {
            if event.buttonNumber == 0 {
                dragPanning = false
            }
            super.mouseUp(with: event)
        }
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
