//
//  CommandKeyHeldMonitor.swift
//  Zenith
//

import AppKit
import SwiftUI

/// Suit l’état de la touche ⌘ dans la fenêtre (local monitor).
struct CommandKeyHeldMonitor: NSViewRepresentable {
    @Binding var isHeld: Bool
    var onFlagsChanged: ((NSEvent.ModifierFlags) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(isHeld: $isHeld, onFlagsChanged: onFlagsChanged)
    }

    func makeNSView(context: Context) -> MonitorHostView {
        let v = MonitorHostView()
        v.coordinator = context.coordinator
        return v
    }

    func updateNSView(_ nsView: MonitorHostView, context: Context) {
        context.coordinator.isHeld = $isHeld
        context.coordinator.onFlagsChanged = onFlagsChanged
        nsView.coordinator = context.coordinator
    }

    final class Coordinator: NSObject {
        var isHeld: Binding<Bool>
        var onFlagsChanged: ((NSEvent.ModifierFlags) -> Void)?
        private var monitor: Any?

        init(isHeld: Binding<Bool>, onFlagsChanged: ((NSEvent.ModifierFlags) -> Void)?) {
            self.isHeld = isHeld
            self.onFlagsChanged = onFlagsChanged
        }

        func startMonitoringIfNeeded(view: MonitorHostView) {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                guard let self else { return event }
                let down = event.modifierFlags.contains(.command)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.isHeld.wrappedValue = down
                    self.onFlagsChanged?(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
                }
                return event
            }
            sync(from: NSApp.currentEvent?.modifierFlags)
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        func sync(from flags: NSEvent.ModifierFlags?) {
            let down = flags?.contains(.command) ?? false
            if isHeld.wrappedValue != down {
                isHeld.wrappedValue = down
            }
        }
    }

    final class MonitorHostView: NSView {
        weak var coordinator: Coordinator?

        override var isOpaque: Bool { false }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                coordinator?.startMonitoringIfNeeded(view: self)
                coordinator?.sync(from: NSApp.currentEvent?.modifierFlags)
            } else {
                coordinator?.stopMonitoring()
            }
        }

        deinit {
            coordinator?.stopMonitoring()
        }
    }
}
