//
//  FilmstripView.swift
//  Zenith
//

@preconcurrency import AppKit
import SwiftUI

struct FilmstripView: View {
    let photos: [PhotoRecord]
    @Binding var selection: UUID?

    /// Hauteur fixe de chaque vignette : la largeur, elle, varie selon le ratio natif de la photo.
    private let thumbHeight: CGFloat = 72

    /// Ancre de défilement au clavier (flèches) : suit la sélection quand l’utilisateur tape une vignette.
    @State private var keyboardScrollAnchor: UUID?
    @State private var filmstripHovering = false
    @State private var keyboardArmed = false

    /// Key codes AppKit : flèche gauche / droite.
    private let leftArrowKeyCode: UInt16 = 123
    private let rightArrowKeyCode: UInt16 = 124

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(photos) { photo in
                        FilmstripCell(
                            photo: photo,
                            isSelected: selection == photo.id,
                            height: thumbHeight
                        )
                        .id(photo.id)
                        .onTapGesture {
                            selection = photo.id
                            keyboardArmed = true
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .contentShape(Rectangle())
            .onHover { inside in
                filmstripHovering = inside
            }
            .background {
                PhotoTriageKeyMonitor { event in
                    handleFilmstripArrowKeyDown(event, proxy: proxy)
                }
            }
            .onChange(of: selection) { _, new in
                if let new {
                    keyboardScrollAnchor = new
                }
            }
            .onChange(of: photos.map(\.id)) { _, _ in
                syncKeyboardAnchorWithPhotos()
            }
            .onAppear {
                syncKeyboardAnchorWithPhotos()
                keyboardArmed = true
            }
            .onDisappear {
                filmstripHovering = false
                keyboardArmed = false
            }
        }
        .frame(height: thumbHeight + 36)
        /// Fond unifié : le conteneur parent (`MainWorkspaceView.filmstripContainer`) applique déjà `liquidSidebarGlass`.
    }

    private func handleFilmstripArrowKeyDown(_ event: NSEvent, proxy: ScrollViewProxy) -> Bool {
        guard !PhotoTriageKeyMonitor.isTextEditingActive() else { return false }
        guard filmstripHovering || keyboardArmed else { return false }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.intersection([.command, .option, .control]).isEmpty else { return false }
        if event.keyCode == leftArrowKeyCode {
            return scrollFilmstrip(proxy: proxy, delta: -1) == .handled
        }
        if event.keyCode == rightArrowKeyCode {
            return scrollFilmstrip(proxy: proxy, delta: 1) == .handled
        }
        return false
    }

    private func syncKeyboardAnchorWithPhotos() {
        guard let first = photos.first?.id else {
            keyboardScrollAnchor = nil
            return
        }
        if let sel = selection, photos.contains(where: { $0.id == sel }) {
            keyboardScrollAnchor = sel
        } else if let a = keyboardScrollAnchor, photos.contains(where: { $0.id == a }) {
            return
        } else {
            keyboardScrollAnchor = first
        }
    }

    private func scrollFilmstrip(proxy: ScrollViewProxy, delta: Int) -> KeyPress.Result {
        guard photos.count > 1 else { return .ignored }
        let anchor = selection ?? keyboardScrollAnchor ?? photos[0].id
        guard let i = photos.firstIndex(where: { $0.id == anchor }) else { return .ignored }
        let j = min(max(0, i + delta), photos.count - 1)
        guard j != i else { return .ignored }
        let id = photos[j].id
        selection = id
        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo(id, anchor: .center)
        }
        keyboardScrollAnchor = id
        return .handled
    }
}

private struct FilmstripCell: View {
    let photo: PhotoRecord
    let isSelected: Bool
    /// Hauteur visible de la vignette ; la largeur s’adapte au ratio natif de la photo (mêmes règles
    /// que la grille bibliothèque : on ne déforme jamais l’image, on ne la rogne pas).
    let height: CGFloat

    @State private var thumb: NSImage?

    /// Largeur dérivée du ratio natif de la photo, bornée pour éviter les vignettes excessivement étroites
    /// (portraits 9:16 → ~40 pt) ou démesurément larges (panoramas → ~144 pt).
    /// Si les dimensions du fichier ne sont pas (encore) renseignées, on retombe sur un cadre carré.
    private var width: CGFloat {
        let h = max(photo.pixelHeight, 1)
        let w = max(photo.pixelWidth, 1)
        guard photo.pixelHeight > 0, photo.pixelWidth > 0 else { return height }
        let aspect = CGFloat(w) / CGFloat(h)
        let raw = height * aspect
        return max(40, min(144, raw))
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumb {
                        Image(nsImage: thumb)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Color.primary.opacity(0.08)
                    }
                }
                .frame(width: width, height: height)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? ZenithTheme.accent : Color.clear, lineWidth: 2)
                }

                if photo.rating > 0 {
                    Text(String(repeating: "★", count: photo.rating))
                        .font(.caption2)
                        .padding(4)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }

            Text(photo.filename)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: width)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(photo.filename), \(photo.rating) étoiles")
        .task(id: cellTaskKey) {
            await loadThumb()
        }
    }

    /// Recharge la vignette quand la photo change ou quand ses réglages développement sont modifiés.
    private var cellTaskKey: String {
        "\(photo.id.uuidString)-\(photo.developBlob.hashValue)"
    }

    /// Cible pixel modérée pour la pellicule (1.5 × le grand côté) : la pellicule défile horizontalement
    /// très souvent ; on privilégie la fluidité quitte à perdre un peu de finesse.
    private var pixelTarget: CGFloat {
        max(width, height) * 1.5
    }

    private func loadThumb() async {
        let devHash = photo.developBlob.hashValue
        let settings = photo.developSettings
        let isNeutral = settings == .neutral

        if !isNeutral {
            do {
                try await Task.sleep(for: .milliseconds(110))
            } catch {
                return
            }
        }

        do {
            let url = try photo.resolvedURL()
            let key = ThumbnailLoader.cacheKey(
                url: url,
                maxPixel: pixelTarget,
                developHash: isNeutral ? nil : devHash
            )
            if let cached = ThumbnailCache.shared.image(forKey: key) {
                self.thumb = cached
                return
            }

            let target = pixelTarget
            /// Propagation d’annulation + throttle : limite stricte du nombre de décodes RAW concurrents.
            /// Sans ce throttle, ouvrir l’app avec une pellicule visible déclenche une avalanche de
            /// décodes simultanés qui peuvent deadlocker `RawCamera-Provider-Render-Queue` et empêcher
            /// le commit de la fenêtre principale.
            let detached = Task.detached(priority: .userInitiated) {
                () async -> ThumbnailDecodeResult in
                if Task.isCancelled { return ThumbnailDecodeResult(nil) }
                do {
                    try await ThumbnailDecodeThrottle.shared.acquire()
                } catch {
                    return ThumbnailDecodeResult(nil)
                }
                if Task.isCancelled {
                    await ThumbnailDecodeThrottle.shared.release()
                    return ThumbnailDecodeResult(nil)
                }
                let started = url.startAccessingSecurityScopedResource()
                let image: NSImage?
                if isNeutral {
                    image = ThumbnailLoader.thumbnail(for: url, maxPixel: target)
                } else {
                    image = ThumbnailLoader.developedThumbnail(for: url, settings: settings, cacheHash: devHash, maxPixel: target)
                }
                if started { url.stopAccessingSecurityScopedResource() }
                await ThumbnailDecodeThrottle.shared.release()
                return ThumbnailDecodeResult(image)
            }

            let result: ThumbnailDecodeResult = await withTaskCancellationHandler {
                await detached.value
            } onCancel: {
                detached.cancel()
            }

            if Task.isCancelled { return }
            self.thumb = result.image
        } catch {
            self.thumb = nil
        }
    }
}
