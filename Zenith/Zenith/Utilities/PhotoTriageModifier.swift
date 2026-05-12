//
//  PhotoTriageModifier.swift
//  Zenith
//

import AppKit
import SwiftData
import SwiftUI

/// ViewModifier qui branche le moniteur de triage clavier (X/U/P/0-5/Suppr) sur n'importe quelle vue.
/// Quand plusieurs photos sont sélectionnées, les actions de notation et de drapeau s'appliquent à toutes.
struct PhotoTriageModifier: ViewModifier {
    let selectedPhotos: [PhotoRecord]
    let modelContext: ModelContext
    var onDeleteRequested: (() -> Void)? = nil

    /// Codes de touche AppKit pour Delete / Forward Delete.
    private let deleteKeyCode: UInt16 = 51
    private let forwardDeleteKeyCode: UInt16 = 117

    func body(content: Content) -> some View {
        content
            .background {
                PhotoTriageKeyMonitor { event in
                    handleKeyDown(event)
                }
            }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard !PhotoTriageKeyMonitor.isTextEditingActive() else { return false }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if event.keyCode == deleteKeyCode || event.keyCode == forwardDeleteKeyCode {
            guard !selectedPhotos.isEmpty, let onDeleteRequested else { return false }
            onDeleteRequested()
            return true
        }

        guard mods.intersection([.command, .option]).isEmpty else { return false }
        guard !selectedPhotos.isEmpty else { return false }

        let raw = event.charactersIgnoringModifiers?.lowercased() ?? ""
        guard let ch = raw.first else { return false }

        switch ch {
        case "x":
            applyToAll { $0.flag = .reject }
        case "u":
            applyToAll {
                $0.rating = 0
                $0.flag = .none
            }
        case "p":
            applyToAll { $0.flag = .pick }
        case "0", "1", "2", "3", "4", "5":
            let value = Int(String(ch)) ?? 0
            applyToAll { $0.rating = value }
        default:
            return false
        }
        try? modelContext.save()
        return true
    }

    private func applyToAll(_ mutate: (PhotoRecord) -> Void) {
        for photo in selectedPhotos {
            mutate(photo)
        }
    }
}

extension View {
    /// Applique les raccourcis triage à toutes les photos sélectionnées (et optionnellement la suppression via Suppr).
    func photoTriageKeyboard(
        photos: [PhotoRecord],
        modelContext: ModelContext,
        onDeleteRequested: (() -> Void)? = nil
    ) -> some View {
        modifier(PhotoTriageModifier(
            selectedPhotos: photos,
            modelContext: modelContext,
            onDeleteRequested: onDeleteRequested
        ))
    }
}
