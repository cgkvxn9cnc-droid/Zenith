//
//  WindowChromeConfigurator.swift
//  Zenith
//

import AppKit
import SwiftUI

// MARK: - AppKit chrome (barre de titre / plein contenu)

enum ZenithWindowChrome {
    /// Applique le masquage de barre de titre + contenu sous les boutons système (correctif Tahoe / fenêtres SwiftUI).
    static func apply(to window: NSWindow) {
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
        }
        // `true` fait déplacer la fenêtre depuis presque tout le fond « vide » : en conflit avec pan / sliders / grille.
        // La barre de titre système (zone des feux) reste utilisable pour déplacer la fenêtre.
        window.isMovableByWindowBackground = false
        // Même base d’apparence que le contenu SwiftUI (`.preferredColorScheme(.dark)`) : évite que titre / vibrance
        // suivent le thème système et fassent varier la luminosité de la zone chrome.
        window.appearance = NSAppearance(named: .darkAqua)
        // Évite la bande grise opaque (SwiftUI / cadre fenêtre) derrière la barre titre « transparente ».
        window.isOpaque = false
        window.backgroundColor = .clear
        if let root = window.contentView {
            root.wantsLayer = true
            root.layer?.backgroundColor = NSColor.clear.cgColor
        }
        // Évite une barre d’outils SwiftUI implicite qui réserve une bande sous le titre.
        window.toolbar = nil
        // S’assurer que les boutons système restent visibles (`.plain` les fait disparaître ; on ne les masque jamais ici).
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
    }

    static func refreshAllWindows() {
        for window in NSApplication.shared.windows {
            apply(to: window)
        }
    }
}

// MARK: - Délégue : SwiftUI crée la fenêtre après le lancement ; on rattrape toute fenêtre clé / différée

final class ZenithAppDelegate: NSObject, NSApplicationDelegate {
    private var keyObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { note in
            if let window = note.object as? NSWindow {
                ZenithWindowChrome.apply(to: window)
            }
        }

        ZenithWindowChrome.refreshAllWindows()
        DispatchQueue.main.async {
            ZenithWindowChrome.refreshAllWindows()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            ZenithWindowChrome.refreshAllWindows()
        }
    }

    deinit {
        if let keyObserver {
            NotificationCenter.default.removeObserver(keyObserver)
        }
    }
}

// MARK: - Ancre SwiftUI : la fenêtre n’existe pas toujours au premier `updateNSView`

private final class WindowChromeAnchorView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            ZenithWindowChrome.apply(to: window)
        }
    }
}

/// Réapplique le chrome dès que la vue est attachée à une `NSWindow`.
struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowChromeAnchorView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            ZenithWindowChrome.apply(to: window)
        } else {
            DispatchQueue.main.async {
                if let window = nsView.window {
                    ZenithWindowChrome.apply(to: window)
                }
            }
        }
    }
}
