//
//  LibraryGridView.swift
//  Zenith
//

@preconcurrency import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Décrit comment un clic sur une cellule doit modifier la sélection.
enum LibrarySelectionMode {
    /// Clic simple : remplace la sélection par cette photo.
    case single
    /// Cmd + clic : bascule cette photo dans la sélection (ajout ou retrait).
    case toggle
    /// Maj + clic : sélectionne la plage du précédent ancrage à cette photo.
    case range
}

/// Cible disponible pour l’action « Déplacer vers » dans le menu contextuel.
/// On véhicule un `Identifiable` léger (id + nom) plutôt que `CollectionRecord`, pour ne pas réinvalider
/// les cellules quand SwiftData met à jour des champs sans rapport avec ce menu.
struct LibraryCollectionTarget: Identifiable, Hashable {
    let id: UUID
    let name: String
    /// Profondeur dans la hiérarchie : permet d’indenter visuellement les sous-dossiers du menu.
    let depth: Int
}

/// Données minimales nécessaires à l'affichage d'une cellule de bibliothèque.
/// Évite de passer le `@Model PhotoRecord` complet à chaque cellule, ce qui limite les invalidations SwiftUI
/// pendant le défilement d'une grande grille.
private struct LibraryGridItemSnapshot: Identifiable, Equatable {
    let id: UUID
    let filename: String
    let fileBookmark: Data
    let developHash: Int
    let rating: Int
    let flag: PhotoPickFlag

    init(photo: PhotoRecord) {
        id = photo.id
        filename = photo.filename
        fileBookmark = photo.fileBookmark
        developHash = photo.developBlob.hashValue
        rating = photo.rating
        flag = photo.flag
    }

    func resolvedURL() throws -> URL {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: fileBookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        if stale { throw BookmarkResolutionError.stale }
        return url
    }
}

/// Collecteur thread-safe pour les URL reçues depuis `NSItemProvider`.
/// Les callbacks `loadObject` peuvent arriver en parallèle ; muter directement un tableau capturé déclenche
/// des erreurs Swift 6 de concurrence.
private final class DroppedURLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        storage.append(url)
        lock.unlock()
    }

    func snapshot() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

struct LibraryGridView: View {
    let photos: [PhotoRecord]
    @Binding var selectedPhotoID: UUID?
    @Binding var selectedPhotoIDs: Set<UUID>
    var thumbSize: CGFloat = 148
    /// Espace réservé en haut pour ne pas passer sous la barre chrome flottante.
    var topContentInset: CGFloat = 0
    /// Marge horizontale dans la colonne centrale (alignée sur les marges des colonnes latérales).
    var horizontalGutter: CGFloat = ZenithTheme.sidebarColumnHorizontalPadding
    /// Demande la suppression d'un ensemble de photos (présente la boîte de confirmation au parent).
    var onRequestDelete: (Set<UUID>) -> Void = { _ in }
    /// Réceptionne un dépôt d’URL (drag/drop Finder) ; renvoie `true` si au moins un fichier a été pris en charge.
    var onDropURLs: ([URL]) -> Bool = { _ in false }
    /// Liste plate des collections utilisateur affichables dans le menu contextuel « Déplacer vers ».
    /// L’ordre et l’indentation reflètent la hiérarchie présentée dans la sidebar.
    var collectionTargets: [LibraryCollectionTarget] = []
    /// Déplace un ensemble de photos vers une collection existante (`collectionID`).
    var onMoveToCollection: (Set<UUID>, UUID) -> Void = { _, _ in }
    /// Demande au parent d’ouvrir la modale « Nouvelle collection » et d’y assigner ces photos après création.
    var onMoveToNewCollection: (Set<UUID>) -> Void = { _ in }
    /// Double-clic sur une vignette : ouvrir en Développement (photo ciblée en focus).
    var onOpenInDevelop: (UUID) -> Void = { _ in }

    /// Espacement vertical compact entre les vignettes (6 pt) : on resserre la grille pour gagner en densité,
    /// tout en gardant l’espacement horizontal d’origine pour la respiration visuelle entre colonnes.
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbSize + 16), spacing: 14, alignment: .top)]
    }

    /// État de survol pendant un drag/drop : sert à dessiner un cadre d’invitation autour de la grille.
    @State private var isDropTargeted = false

    @MainActor
    private var items: [LibraryGridItemSnapshot] {
        photos.map(LibraryGridItemSnapshot.init(photo:))
    }

    var body: some View {
        Group {
            if photos.isEmpty {
                ContentUnavailableView {
                    Label("library.grid.empty.title", systemImage: "photo.on.rectangle.angled")
                } description: {
                    Text("library.grid.empty.subtitle")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, horizontalGutter)
                .padding(.top, topContentInset)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(items) { item in
                            LibraryGridCell(
                                item: item,
                                thumbSize: thumbSize,
                                isPrimary: selectedPhotoID == item.id,
                                isSelected: selectedPhotoIDs.contains(item.id),
                                collectionTargets: collectionTargets,
                                onSelect: { mode in handleSelection(id: item.id, mode: mode) },
                                onOpenInDevelop: { onOpenInDevelop(item.id) },
                                onRequestDelete: { requestDeletionContext(for: item.id) },
                                onRequestMoveToCollection: { targetID in
                                    onMoveToCollection(actionContext(for: item.id), targetID)
                                },
                                onRequestMoveToNewCollection: {
                                    onMoveToNewCollection(actionContext(for: item.id))
                                }
                            )
                        }
                    }
                    .padding(.horizontal, horizontalGutter)
                    .padding(.top, max(horizontalGutter, topContentInset))
                    .padding(.bottom, max(horizontalGutter, 24))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ZenithTheme.pageBackground)
        /// Drop handler : on accepte n’importe quelle URL de fichier ; le filtrage par extension a lieu côté `PhotoImporter`.
        /// L’affichage d’une bordure accentuée signale visuellement que le drop sera accepté.
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(ZenithTheme.accent, lineWidth: 3)
                    .padding(8)
                    .overlay(alignment: .top) {
                        Label("library.drop.hint", systemImage: "square.and.arrow.down.on.square")
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                            .overlay(Capsule(style: .continuous).strokeBorder(ZenithTheme.accent.opacity(0.6), lineWidth: 1))
                            .padding(.top, max(topContentInset, 16))
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isDropTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    /// Récupère les URL fichier des `NSItemProvider` puis délègue à `onDropURLs`.
    /// Le décodage se fait en asynchrone (`loadObject`) ; on rebascule sur le main actor avant d’appeler le handler.
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        let collector = DroppedURLCollector()
        let group = DispatchGroup()
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { collector.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let urls = collector.snapshot()
            guard !urls.isEmpty else { return }
            _ = onDropURLs(urls)
        }
        return true
    }

    private func handleSelection(id photoID: UUID, mode: LibrarySelectionMode) {
        switch mode {
        case .single:
            selectedPhotoIDs = [photoID]
            selectedPhotoID = photoID
        case .toggle:
            if selectedPhotoIDs.contains(photoID) {
                selectedPhotoIDs.remove(photoID)
                if selectedPhotoID == photoID {
                    selectedPhotoID = selectedPhotoIDs.first
                }
            } else {
                selectedPhotoIDs.insert(photoID)
                selectedPhotoID = photoID
            }
        case .range:
            let anchor = selectedPhotoID ?? selectedPhotoIDs.first
            if let anchor,
               let i = photos.firstIndex(where: { $0.id == anchor }),
               let j = photos.firstIndex(where: { $0.id == photoID }) {
                let range = i <= j ? i ... j : j ... i
                selectedPhotoIDs = Set(photos[range].map(\.id))
                selectedPhotoID = photoID
            } else {
                selectedPhotoIDs = [photoID]
                selectedPhotoID = photoID
            }
        }
    }

    /// Si la photo cible fait partie d'une multi-sélection on supprime tout, sinon on cible cette photo seulement.
    private func requestDeletionContext(for photoID: UUID) {
        if selectedPhotoIDs.contains(photoID), selectedPhotoIDs.count > 1 {
            onRequestDelete(selectedPhotoIDs)
        } else {
            onRequestDelete([photoID])
        }
    }

    /// Détermine sur quelles photos doit s’appliquer une action contextuelle (déplacement, etc.).
    /// Règle : si la cellule cible est déjà dans la multi-sélection, on agit sur toute la sélection ;
    /// sinon on agit uniquement sur cette photo (pour ne pas surprendre l’utilisateur lorsqu’il fait un
    /// clic droit sur une cellule non sélectionnée).
    private func actionContext(for photoID: UUID) -> Set<UUID> {
        if selectedPhotoIDs.contains(photoID), selectedPhotoIDs.count > 1 {
            return selectedPhotoIDs
        }
        return [photoID]
    }
}

private struct LibraryGridCell: View {
    let item: LibraryGridItemSnapshot
    let thumbSize: CGFloat
    /// Photo ayant le focus (synchronisée avec Develop / Métadonnées).
    let isPrimary: Bool
    /// Photo incluse dans la multi-sélection courante.
    let isSelected: Bool
    /// Cibles disponibles pour le sous-menu « Déplacer vers ».
    let collectionTargets: [LibraryCollectionTarget]
    let onSelect: (LibrarySelectionMode) -> Void
    let onOpenInDevelop: () -> Void
    let onRequestDelete: () -> Void
    /// Demande de déplacement vers une collection existante (id passé par le menu).
    let onRequestMoveToCollection: (UUID) -> Void
    /// Demande de création d’une nouvelle collection contenant les photos ciblées.
    let onRequestMoveToNewCollection: () -> Void

    @State private var thumb: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let thumb {
                    Image(nsImage: thumb)
                        .resizable()
                        .interpolation(.low)
                        .scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                }
            }
            .frame(width: thumbSize, height: thumbSize)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            }
            .overlay(alignment: .topLeading) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white, ZenithTheme.accent)
                        .padding(6)
                }
            }
            .overlay(alignment: .topTrailing) {
                if item.flag != .none {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(item.flag == .pick ? Color.green : Color.red)
                        .padding(5)
                        .background(Color.black.opacity(0.28), in: Circle())
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if item.rating > 0 {
                    Text(String(repeating: "★", count: item.rating))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.32), in: Capsule())
                        .padding(6)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .highPriorityGesture(
                TapGesture(count: 2).onEnded {
                    onOpenInDevelop()
                }
            )
            .onTapGesture {
                let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let mode: LibrarySelectionMode
                if flags.contains(.command) {
                    mode = .toggle
                } else if flags.contains(.shift) {
                    mode = .range
                } else {
                    mode = .single
                }
                onSelect(mode)
            }
            .contextMenu {
                Menu {
                    Button {
                        onRequestMoveToNewCollection()
                    } label: {
                        Label("library.grid.move.new", systemImage: "folder.badge.plus")
                    }
                    if !collectionTargets.isEmpty {
                        Divider()
                        ForEach(collectionTargets) { target in
                            Button {
                                onRequestMoveToCollection(target.id)
                            } label: {
                                /// Préfixe d’indentation simple pour conserver la lecture hiérarchique
                                /// sans recourir à un menu imbriqué (qui coûte cher visuellement).
                                let prefix = String(repeating: "    ", count: max(0, target.depth))
                                Label("\(prefix)\(target.name)", systemImage: "folder")
                            }
                        }
                    }
                } label: {
                    Label("library.grid.move", systemImage: "tray.and.arrow.down")
                }

                Divider()

                Button(role: .destructive) {
                    onRequestDelete()
                } label: {
                    Label("library.grid.delete", systemImage: "trash")
                }
            }

            Text(item.filename)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: thumbSize, alignment: .leading)
                .foregroundStyle(.primary)
        }
        .task(id: cellTaskKey) {
            await loadThumb()
        }
    }

    private var borderColor: Color {
        if isPrimary { return ZenithTheme.accent }
        if isSelected { return ZenithTheme.accent.opacity(0.7) }
        return Color.primary.opacity(0.12)
    }

    private var borderWidth: CGFloat {
        isPrimary ? 2.5 : (isSelected ? 2 : 1)
    }

    /// Recharge la vignette quand la photo change, quand la taille passe un palier, ou quand les réglages changent.
    /// Le palier de taille (`/ 32`) évite de recharger pour 1 pt de différence du slider.
    private var cellTaskKey: String {
        "\(item.id.uuidString)-\(Int(thumbSize / 40))-\(item.developHash)"
    }

    /// Cible très modeste : la bibliothèque privilégie la fluidité du scroll à la précision pixel-perfect.
    /// Les aperçus détaillés restent disponibles dans Développement ; ici, ~0,8× suffit pour identifier les images.
    private var pixelTarget: CGFloat {
        min(160, max(72, thumbSize * 0.8))
    }

    private func loadThumb() async {
        /// En bibliothèque, on charge volontairement une miniature brute basse résolution.
        /// C'est beaucoup plus fluide que d'appliquer le pipeline de développement sur chaque cellule visible.
        do {
            let url = try item.resolvedURL()
            let key = ThumbnailLoader.cacheKey(
                url: url,
                maxPixel: pixelTarget
            )
            if let cached = ThumbnailCache.shared.image(forKey: key) {
                self.thumb = cached
                return
            }

            let target = pixelTarget
            /// `Task.detached` libère MainActor mais n’hérite pas de l’annulation parente. On la propage
            /// manuellement via `withTaskCancellationHandler` : dès que la cellule sort de l’écran ou que
            /// `task(id:)` change de clé, la tâche détachée est annulée et libère le slot du throttle.
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
                let image = ThumbnailLoader.thumbnail(for: url, maxPixel: target)
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
