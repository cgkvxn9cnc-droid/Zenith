//
//  PhotoTriageKeyMonitor.swift
//  Zenith
//

import AppKit
import SwiftUI

/// Intercepte les frappes triage (X / U / P / 0–5) au niveau AppKit : les `ScrollView` et la grille
/// absorbent souvent les événements avant `onKeyPress` sur la vue racine SwiftUI.
struct PhotoTriageKeyMonitor: NSViewRepresentable {
    /// Retourne `true` si la touche a été consommée (ne pas propager).
    var onKeyDown: (NSEvent) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onKeyDown: onKeyDown)
    }

    func makeNSView(context: Context) -> MonitorHostView {
        let v = MonitorHostView()
        v.coordinator = context.coordinator
        return v
    }

    func updateNSView(_ nsView: MonitorHostView, context: Context) {
        context.coordinator.onKeyDown = onKeyDown
        nsView.coordinator = context.coordinator
    }

    /// Ne pas traiter les raccourcis quand un champ texte est actif (chat, formulaires, recherche).
    static func isTextEditingActive() -> Bool {
        guard let fr = NSApp.keyWindow?.firstResponder else { return false }
        if fr is NSTextView { return true }
        if fr is NSTextField { return true }
        return false
    }

    final class Coordinator: NSObject {
        var onKeyDown: (NSEvent) -> Bool
        private var monitor: Any?

        init(onKeyDown: @escaping (NSEvent) -> Bool) {
            self.onKeyDown = onKeyDown
        }

        func startMonitoringIfNeeded() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                if self.onKeyDown(event) {
                    return nil
                }
                return event
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            stopMonitoring()
        }
    }

    final class MonitorHostView: NSView {
        weak var coordinator: Coordinator?

        override var isOpaque: Bool { false }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                coordinator?.startMonitoringIfNeeded()
            } else {
                coordinator?.stopMonitoring()
            }
        }

        deinit {
            coordinator?.stopMonitoring()
        }
    }
}
