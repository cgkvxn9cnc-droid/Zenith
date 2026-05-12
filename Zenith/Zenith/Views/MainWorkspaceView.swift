//
//  MainWorkspaceView.swift
//  Zenith
//

import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct MainWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PhotoRecord.addedAt, order: .reverse) private var photos: [PhotoRecord]
    @Query(sort: \CollectionRecord.sortIndex) private var collections: [CollectionRecord]

    @AppStorage("zenith.fontScaleStep") private var fontScaleStep = 3
    @AppStorage("zenith.collaborationEnabled") private var collaborationEnabled = false
    @AppStorage("zenith.leftSidebarVisible") private var leftSidebarVisible = true
    @AppStorage("zenith.rightSidebarVisible") private var rightSidebarVisible = true
    @AppStorage("zenith.workspaceMode") private var persistedWorkspaceModeRaw = WorkspaceTab.library.rawValue
    @AppStorage("zenith.lastSelectedPhotoID") private var persistedPhotoID = ""
    @AppStorage("zenith.libraryThumbSize") private var libraryThumbSize: Double = 148
    @AppStorage("zenith.filmstripVisible") private var filmstripVisible = true

    @State private var sidebarSelection: SidebarSelection?
    @State private var showInviteSheet = false
    @State private var showExportSheet = false
    @State private var photoImportFailureMessage: String?
    @State private var developCompareOriginal = false
    @State private var previewZoomScale: CGFloat = 1.0
    @State private var developCanvasTool: DevelopCanvasTool = .none
    @State private var showNewCollectionSheet = false
    @State private var newCollectionName = ""
    /// Photos à assigner après création d’une nouvelle collection via le menu contextuel
    /// « Déplacer vers → Nouvelle collection ». Vide en dehors de ce flux.
    @State private var pendingMoveIDs: Set<UUID> = []
    @State private var zoomFieldText = ""
    /// Sélection multiple (Cmd+clic / Maj+clic) en plus du focus single-photo.
    @State private var selectedPhotoIDs: Set<UUID> = []
    /// Demande de suppression en attente (présente la boîte de confirmation à deux choix).
    @State private var pendingPhotoDeletion: PendingPhotoDeletion?
    /// État de l'export par lot : `isExporting` remplace l'icône export par un cercle de progression.
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    @State private var exportTask: Task<Void, Never>?
    @FocusState private var focusWorkspace: Bool
    @FocusState private var zoomFieldFocused: Bool

    private var workspaceMode: WorkspaceTab {
        WorkspaceTab(rawValue: persistedWorkspaceModeRaw) ?? .library
    }

    private var workspaceModeBinding: Binding<WorkspaceTab> {
        Binding(
            get: { WorkspaceTab(rawValue: persistedWorkspaceModeRaw) ?? .library },
            set: { persistedWorkspaceModeRaw = $0.rawValue }
        )
    }

    private var selectedPhotoID: UUID? {
        guard !persistedPhotoID.isEmpty,
              let id = UUID(uuidString: persistedPhotoID) else { return nil }
        return id
    }

    private var selectedPhotoIDBinding: Binding<UUID?> {
        Binding(
            get: { selectedPhotoID },
            set: { newValue in
                if let id = newValue {
                    persistedPhotoID = id.uuidString
                    if !selectedPhotoIDs.contains(id) {
                        selectedPhotoIDs = [id]
                    }
                } else {
                    persistedPhotoID = ""
                    selectedPhotoIDs.removeAll()
                }
            }
        )
    }

    /// Photos correspondant à la multi-sélection courante (sinon focus uniquement).
    private var selectedPhotos: [PhotoRecord] {
        if selectedPhotoIDs.isEmpty {
            return selectedPhoto.map { [$0] } ?? []
        }
        return photos.filter { selectedPhotoIDs.contains($0.id) }
    }

    private let previewZoomMin: CGFloat = 0.05
    private let previewZoomMax: CGFloat = 16

    private let libraryThumbSizeMin: Double = 96
    private let libraryThumbSizeMax: Double = 320

    private var supportsRightSidebar: Bool {
        workspaceMode == .library || workspaceMode == .develop
    }
    /// Marge verticale au-dessus et en dessous des barres latérales vitrées.
    private let sidebarVerticalInset: CGFloat = 16
    /// Hauteur de la barre horizontale transparente (zoom, export) au-dessus des colonnes.
    private let topChromeBarHeight: CGFloat = 48
    /// Décalage sous les boutons fermer / réduire / zoom une fois le contenu étendu sous la barre titre.
    private let windowControlsTopInset: CGFloat = 28
    /// Marge horizontale entre le bord de la fenêtre et la barre du haut (verre).
    private let topChromeHorizontalInset: CGFloat = 16

    /// Hauteur réservée sous la barre chrome (alignée sur l’overlay) : sert d’inset au contenu pour qu’il ne démarre pas masqué par la barre.
    /// Plus de bandeau opaque : la barre flotte en verre transparent au-dessus du canevas pour laisser apparaître l’image en arrière-plan.
    private var topChromeBackingBandHeight: CGFloat {
        windowControlsTopInset + topChromeBarHeight
    }

    private let dynamicTypeSteps: [DynamicTypeSize] = [.xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge]

    private var resolvedDynamicType: DynamicTypeSize {
        let idx = min(max(fontScaleStep, 0), dynamicTypeSteps.count - 1)
        return dynamicTypeSteps[idx]
    }

    private var isPhotoImportFailurePresented: Binding<Bool> {
        Binding(
            get: { photoImportFailureMessage != nil },
            set: { isPresented in
                if isPresented == false {
                    photoImportFailureMessage = nil
                }
            }
        )
    }

    /// Catalogue (overview) · Bibliothèque (grille + notation) · Développement (post-production).
    /// Chaque branche est dotée d’une transition `.opacity` : combinée à `animation(value: workspaceMode)`
    /// au niveau du chrome, on obtient un fondu doux quand l’utilisateur change de page.
    @ViewBuilder
    private var mainWorkspaceCanvas: some View {
        switch workspaceMode {
        case .catalog:
            CatalogOverviewView(
                photoCount: photos.count,
                collectionFolderCount: collections.count,
                onImportPhotos: { runImport() },
                onImportLightroom: { runLightroomImport() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        case .library:
            LibraryGridView(
                photos: filteredPhotos,
                selectedPhotoID: selectedPhotoIDBinding,
                selectedPhotoIDs: $selectedPhotoIDs,
                thumbSize: CGFloat(libraryThumbSize),
                topContentInset: topChromeBackingBandHeight + 8,
                horizontalGutter: ZenithTheme.sidebarColumnHorizontalPadding,
                onRequestDelete: { ids in
                    requestPhotoDeletion(ids: ids)
                },
                onDropURLs: { urls in
                    runImport(droppedURLs: urls)
                    return true
                },
                collectionTargets: userCollectionTargets,
                onMoveToCollection: { ids, targetID in
                    movePhotos(ids: ids, toCollection: targetID)
                },
                onMoveToNewCollection: { ids in
                    requestMoveToNewCollection(ids: ids)
                },
                onOpenInDevelop: { id in
                    persistedPhotoID = id.uuidString
                    selectedPhotoIDs = [id]
                    persistedWorkspaceModeRaw = WorkspaceTab.develop.rawValue
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        case .develop:
            /// Rendu plein écran derrière le chrome : voir `developWorkspaceChrome`.
            EmptyView()
        }
    }

    /// Aperçu développement : calque plein cadre derrière le chrome (remplace l’ancienne colonne centrale).
    @ViewBuilder
    private var developBackgroundPhotoPreview: some View {
        PhotoPreviewView(
            photo: selectedPhoto,
            compareOriginal: developCompareOriginal,
            zoomScale: $previewZoomScale,
            developCanvasTool: $developCanvasTool,
            onHealTapNormalized: { x, y in
                applyHealTapFromPreview(x: x, y: y)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    /// Développement : la photo remplit la fenêtre sous la barre, les colonnes vitrées et la pellicule ; le centre du `HStack` est transparent pour le zoom et le pan sur l’aperçu.
    @ViewBuilder
    private var developWorkspaceChrome: some View {
        ZStack {
            developBackgroundPhotoPreview
                .zIndex(0)

            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    HStack(alignment: .top, spacing: 0) {
                        if leftSidebarVisible {
                            leftGlassSidebar
                                .frame(width: ZenithTheme.sidebarLeadingColumnWidth)
                                .frame(maxHeight: .infinity, alignment: .topLeading)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                        }

                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .layoutPriority(1)
                            .allowsHitTesting(false)

                        if rightSidebarVisible {
                            rightGlassSidebar
                                .frame(width: ZenithTheme.sidebarTrailingColumnWidth)
                                .frame(maxHeight: .infinity, alignment: .topLeading)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, windowControlsTopInset + topChromeBarHeight + sidebarVerticalInset)
                    .padding(.horizontal, topChromeHorizontalInset)
                    .padding(.bottom, sidebarVerticalInset)
                    .overlay {
                        sidebarCollapseHandlesOverlay
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .animation(.snappy(duration: 0.22), value: leftSidebarVisible)
                    .animation(.snappy(duration: 0.22), value: rightSidebarVisible)
                }
                .overlay(alignment: .top) {
                    HStack(alignment: .center, spacing: 12) {
                        workspaceModeChromeIconsLeading
                            .padding(.leading, topChromeHorizontalInset)

                        topWorkspaceChromeBarGlass
                            .frame(maxWidth: .infinity)

                        trailingExportButtonOutsideBar
                            .padding(.trailing, topChromeHorizontalInset)
                    }
                    .padding(.top, windowControlsTopInset)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                filmstripContainer
            }
            .zIndex(1)
        }
    }

    /// Canevas principal ; barre latérale gauche (navigation) ; droite réservée au développement.
    @ViewBuilder
    private var workspaceChrome: some View {
        Group {
            if workspaceMode == .develop {
                developWorkspaceChrome
            } else {
                catalogOrLibraryWorkspaceChrome
            }
        }
        .frame(minWidth: 900, minHeight: 500)
    }

    /// Catalogue et bibliothèque : grille ou vue d’ensemble dans la colonne centrale (pas d’aperçu plein écran derrière).
    @ViewBuilder
    private var catalogOrLibraryWorkspaceChrome: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                /// Colonnes explicites : le canevas occupe l’espace restant (plus d’insets « double » dans la grille).
                HStack(alignment: .top, spacing: 0) {
                    if leftSidebarVisible, workspaceMode != .catalog {
                        leftGlassSidebar
                            .frame(width: ZenithTheme.sidebarLeadingColumnWidth)
                            .frame(maxHeight: .infinity, alignment: .topLeading)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    mainWorkspaceCanvas
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)

                    if rightSidebarVisible, workspaceMode != .catalog {
                        Group {
                            switch workspaceMode {
                            case .catalog:
                                EmptyView()
                            case .library:
                                libraryMetadataSidebar
                                    .frame(width: ZenithTheme.sidebarTrailingColumnWidth)
                                    .frame(maxHeight: .infinity, alignment: .topLeading)
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                            case .develop:
                                EmptyView()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, windowControlsTopInset + topChromeBarHeight + sidebarVerticalInset)
                .padding(.horizontal, topChromeHorizontalInset)
                .padding(.bottom, sidebarVerticalInset)
                .overlay {
                    sidebarCollapseHandlesOverlay
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .animation(.snappy(duration: 0.22), value: leftSidebarVisible)
                .animation(.snappy(duration: 0.22), value: rightSidebarVisible)
                .animation(.smooth(duration: 0.28), value: workspaceMode)
            }
            .overlay(alignment: .top) {
                HStack(alignment: .center, spacing: 12) {
                    workspaceModeChromeIconsLeading
                        .padding(.leading, topChromeHorizontalInset)

                    topWorkspaceChromeBarGlass
                        .frame(maxWidth: .infinity)

                    trailingExportButtonOutsideBar
                        .padding(.trailing, topChromeHorizontalInset)
                }
                .padding(.top, windowControlsTopInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Conteneur du filmstrip avec poignée de pliage : la flèche reste accessible même barre fermée.
    /// Animation courte (≈ 130 ms) : on veut que la pellicule apparaisse instantanément, sans rebond.
    @ViewBuilder
    private var filmstripContainer: some View {
        VStack(spacing: 0) {
            filmstripCollapseHandle
            if filmstripVisible {
                FilmstripView(photos: filteredPhotos, selection: selectedPhotoIDBinding)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
            }
        }
        .background {
            ZenithTheme.liquidSidebarGlass(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, topChromeHorizontalInset)
        .padding(.bottom, 6)
        .animation(.easeOut(duration: 0.13), value: filmstripVisible)
    }

    private var filmstripCollapseHandle: some View {
        Button {
            filmstripVisible.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: filmstripVisible ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                if !filmstripVisible {
                    Text("workspace.filmstrip.show")
                        .font(.caption.weight(.medium))
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, filmstripVisible ? 14 : 12)
            .padding(.vertical, 4)
            /// Pas de second calque « verre » ici : `filmstripContainer` applique déjà `liquidSidebarGlass` sur tout le bloc ;
            /// une capsule en plus créait un effet de double bouton quand la pellicule était repliée.
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .help(String(localized: filmstripVisible
                        ? "workspace.filmstrip.hide"
                        : "workspace.filmstrip.show"))
        .accessibilityLabel(Text(filmstripVisible
                                    ? "workspace.filmstrip.hide"
                                    : "workspace.filmstrip.show"))
        .padding(.top, filmstripVisible ? 2 : 6)
        .padding(.bottom, filmstripVisible ? 2 : 6)
    }

    /// Poignées centrées sur la hauteur utile des colonnes (même rectangle que le `HStack` des panneaux).
    /// En mode Catalogue : pas de poignées (les colonnes sont absentes, les flèches n’auraient rien à plier).
    private var sidebarCollapseHandlesOverlay: some View {
        GeometryReader { geo in
            let midY = geo.size.height / 2
            let halfHandle: CGFloat = 11
            let leadW = ZenithTheme.sidebarLeadingColumnWidth
            let trailW = ZenithTheme.sidebarTrailingColumnWidth
            let sideInset = topChromeHorizontalInset
            ZStack {
                if workspaceMode != .catalog {
                    sidebarEdgeHandle(
                        systemName: leftSidebarVisible ? "chevron.left" : "chevron.right",
                        helpKey: leftSidebarVisible ? "workspace.sidebar.hide" : "workspace.sidebar.show",
                        isSidebarVisible: leftSidebarVisible
                    ) {
                        leftSidebarVisible.toggle()
                    }
                    .position(
                        x: leftSidebarVisible ? sideInset + leadW - halfHandle : sideInset + halfHandle,
                        y: midY
                    )
                    .transition(.opacity)

                    if supportsRightSidebar {
                        sidebarEdgeHandle(
                            systemName: rightSidebarVisible ? "chevron.right" : "chevron.left",
                            helpKey: rightSidebarVisible ? "workspace.sidebar.hide" : "workspace.sidebar.show",
                            isSidebarVisible: rightSidebarVisible
                        ) {
                            rightSidebarVisible.toggle()
                        }
                        .position(
                            x: rightSidebarVisible ? geo.size.width - sideInset - trailW + halfHandle : geo.size.width - sideInset - halfHandle,
                            y: midY
                        )
                        .transition(.opacity)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(true)
    }

    private func sidebarEdgeHandle(
        systemName: String,
        helpKey: String,
        isSidebarVisible: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 22, height: 68)
                .background {
                    if !isSidebarVisible {
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
                .overlay {
                    if !isSidebarVisible {
                        Capsule(style: .continuous)
                            .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                    }
                }
                .shadow(color: .black.opacity(isSidebarVisible ? 0 : 0.15), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .help(String(localized: String.LocalizationValue(helpKey)))
        .accessibilityLabel(Text(String(localized: String.LocalizationValue(helpKey))))
    }

    /// Colonne secondaire (vignette de navigation, presets, copier/coller) : enveloppée dans un `ScrollView`
    /// pour que le bloc des presets reste toujours accessible même si l’utilisateur réduit la moitié haute du `VSplitView`.
    @ViewBuilder
    private var developAuxiliaryColumn: some View {
        Group {
            if let photo = selectedPhoto {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        DevelopNavigatorThumb(photo: photo)
                            .padding(.horizontal, ZenithTheme.sidebarColumnHorizontalPadding)
                            .padding(.top, ZenithTheme.sidebarColumnHorizontalPadding)
                        PresetsPanel(photo: photo, selectionTargets: selectedPhotos, compact: true)
                        developCopyPasteToolbar
                            .padding(.horizontal, ZenithTheme.sidebarColumnHorizontalPadding)
                            .padding(.vertical, ZenithTheme.sidebarColumnHorizontalPadding)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                VStack {
                    Spacer(minLength: 0)
                    Text("workspace.select_for_develop")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .padding(ZenithTheme.sidebarColumnHorizontalPadding)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var developCopyPasteToolbar: some View {
        HStack(spacing: 8) {
            Button {
                NotificationCenter.default.post(name: .zenithCopyDevelop, object: nil)
            } label: {
                Label(String(localized: "develop.toolbar.copy"), systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(selectedPhoto == nil)

            Button {
                NotificationCenter.default.post(name: .zenithPasteDevelop, object: nil)
            } label: {
                Label(String(localized: "develop.toolbar.paste"), systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(selectedPhoto == nil)
        }
    }

    /// Sans `NavigationStack` / titre : garde la liste intégrée au panneau verre.
    private var collectionsSidebarNavigation: some View {
        CollectionsSidebar(
            collections: collections,
            photos: photos,
            selection: $sidebarSelection,
            onAddCollection: { showNewCollectionSheet = true },
            onSelect: { newSelection in
                if workspaceMode == .develop {
                    selectPhotoForDevelopSidebar(newSelection)
                    return
                }
                /// Cliquer sur une entrée de la sidebar (Bibliothèque ou collection) bascule
                /// automatiquement en mode Bibliothèque : sinon, depuis Catalogue,
                /// l’utilisateur ne « voit » pas la collection s’ouvrir.
                if workspaceMode != .library {
                    persistedWorkspaceModeRaw = WorkspaceTab.library.rawValue
                }
            }
        )
    }

    @ViewBuilder
    private var leftGlassSidebar: some View {
        VStack(spacing: 0) {
            Group {
                if workspaceMode == .develop {
                    if collaborationEnabled {
                        VSplitView {
                            VSplitView {
                                collectionsSidebarNavigation
                                    .frame(minHeight: 100, idealHeight: 160)
                                developAuxiliaryColumn
                                    .frame(minHeight: 240, idealHeight: 360)
                            }
                            .frame(minHeight: 320)

                            ChatPanel(
                                photos: filteredPhotos,
                                selectedPhotoID: selectedPhotoID
                            )
                            .frame(minHeight: 140)
                        }
                    } else {
                        VSplitView {
                            collectionsSidebarNavigation
                                .frame(minHeight: 100, idealHeight: 160)
                            developAuxiliaryColumn
                                .frame(minHeight: 240, idealHeight: 360)
                        }
                    }
                } else if collaborationEnabled {
                    VSplitView {
                        collectionsSidebarNavigation
                            .frame(minHeight: 200)

                        ChatPanel(
                            photos: filteredPhotos,
                            selectedPhotoID: selectedPhotoID
                        )
                        .frame(minHeight: 160)
                    }
                } else {
                    collectionsSidebarNavigation
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZenithTheme.liquidSidebarGlass(ZenithTheme.sidebarFloatingGlassShape)
        }
        .clipShape(ZenithTheme.sidebarFloatingGlassShape)
    }

    /// Catalogue, Bibliothèque et Développement : icônes **hors** de la barre vitrée (même style, même hauteur).
    private var workspaceModeChromeIconsLeading: some View {
        HStack(alignment: .center, spacing: 8) {
            workspaceModeChromeIconButton(
                tab: .catalog,
                systemImage: "house.fill",
                helpKey: "workspace.catalog.open_help",
                accessibilityLabelKey: "workspace.mode.home_a11y"
            )
            workspaceModeChromeIconButton(
                tab: .library,
                systemImage: "square.grid.2x2.fill",
                helpKey: "workspace.mode.library",
                accessibilityLabelKey: "workspace.mode.library"
            )
            workspaceModeChromeIconButton(
                tab: .develop,
                systemImage: "slider.horizontal.3",
                helpKey: "workspace.mode.develop",
                accessibilityLabelKey: "workspace.mode.develop"
            )
        }
    }

    private func workspaceModeChromeIconButton(
        tab: WorkspaceTab,
        systemImage: String,
        helpKey: String,
        accessibilityLabelKey: String
    ) -> some View {
        Button {
            persistedWorkspaceModeRaw = tab.rawValue
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(workspaceMode == tab ? ZenithTheme.accent : Color.primary)
                .frame(width: topChromeBarHeight, height: topChromeBarHeight)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(WorkspaceChromeOuterIconButtonStyle(cornerRadius: 10))
        .help(Text(LocalizedStringKey(helpKey)))
        .accessibilityLabel(Text(LocalizedStringKey(accessibilityLabelKey)))
    }

    /// Bouton Export : hors barre vitrée, aligné à droite comme pendant « Catalogue » à gauche.
    @ViewBuilder
    private var trailingExportButtonOutsideBar: some View {
        if workspaceMode == .catalog {
            Color.clear
                .frame(width: topChromeBarHeight, height: topChromeBarHeight)
        } else {
            trailingExportButton
        }
    }

    /// Barre du haut (verre) : outils contextuels et notation — les modes (Catalogue / Bibliothèque / Développement) sont les icônes à gauche.
    /// Même fond que les colonnes (`liquidSidebarGlass`) pour une continuité visuelle.
    private var topWorkspaceChromeBarGlass: some View {
        HStack(alignment: .center, spacing: 10) {
            leadingTopChromeCluster

            Spacer(minLength: 8)

            centerTopChromeCluster
                .frame(maxWidth: .infinity)

            Spacer(minLength: 8)

            trailingTopChromeCluster
        }
        .padding(.horizontal, 12)
        .frame(height: topChromeBarHeight)
        .background {
            ZenithTheme.liquidSidebarGlass(ZenithTheme.topChromeGlassShape)
        }
        .clipShape(ZenithTheme.topChromeGlassShape)
    }

    /// Droite de la barre du haut : slider contextuel (zoom en développement, taille vignettes en bibliothèque).
    /// Position uniforme entre Bibliothèque et Développement.
    /// En mode Catalogue : aucun outil de droite (page purement informative ; l’export sauvegarde se fait depuis la page elle-même).
    private var trailingTopChromeCluster: some View {
        HStack(alignment: .center, spacing: 10) {
            switch workspaceMode {
            case .library:
                libraryThumbSizeSliderCluster
            case .develop:
                previewZoomSliderCluster
            case .catalog:
                EmptyView()
            }
        }
        .frame(height: 36, alignment: .center)
    }

    /// Slider de redimensionnement des vignettes (mode bibliothèque uniquement).
    private var libraryThumbSizeSliderCluster: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
            Slider(
                value: $libraryThumbSize,
                in: libraryThumbSizeMin ... libraryThumbSizeMax
            )
            .controlSize(.small)
            .frame(width: 140)
            Image(systemName: "photo.fill")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .help(String(localized: "library.thumb_size.help"))
    }

    /// Système de notation regroupé au centre de la barre (drapeaux + étoiles), uniforme entre Bibliothèque et Développement.
    /// Le badge de multi-sélection apparaît dès que plusieurs photos sont sélectionnées dans ces deux modes.
    /// En mode Catalogue : la notation et le badge sont masqués (la page est purement informative).
    private var centerTopChromeCluster: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            if workspaceMode != .catalog {
                if let photo = selectedPhoto {
                    ratingClusterView(for: photo)
                }
                if multiSelectionCount > 1 {
                    multiSelectionCountBadge
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 36, alignment: .center)
    }

    /// Notation unifiée : drapeaux et étoiles forment un seul système, présentés côte à côte avec un séparateur discret.
    @ViewBuilder
    private func ratingClusterView(for photo: PhotoRecord) -> some View {
        HStack(spacing: 10) {
            flagPicker(for: photo)
            Divider()
                .frame(height: 18)
                .opacity(0.35)
            starPicker(for: photo)
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
    }

    /// Nombre de photos couvertes par les actions groupées (notation, drapeaux, suppression).
    private var multiSelectionCount: Int {
        selectedPhotoIDs.count
    }

    /// Pastille interactive qui rappelle « N photos sélectionnées » et permet de tout désélectionner d’un clic.
    /// L’icône `xmark` finale signale visuellement que c’est une action ; clic vide la multi-sélection
    /// tout en conservant la photo focus (pour ne pas vider le panneau métadonnées / Développement).
    private var multiSelectionCountBadge: some View {
        let format = String(localized: "library.multi_selection.count_format")
        let label = String(format: format, locale: .current, multiSelectionCount)
        return Button {
            clearMultiSelection()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ZenithTheme.accent)
                Text(label)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.10))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(ZenithTheme.accent.opacity(0.45), lineWidth: 1)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .help(String(localized: "library.multi_selection.deselect_help"))
        .accessibilityLabel(Text(label))
        .accessibilityHint(Text("library.multi_selection.deselect_a11y"))
        .accessibilityAddTraits(.isButton)
    }

    /// Vide la multi-sélection : on conserve la photo focus pour ne pas casser le panneau de droite,
    /// tout en effaçant l’état « groupe » qui pilote les actions de notation/déplacement/suppression.
    private func clearMultiSelection() {
        if let id = selectedPhotoID {
            selectedPhotoIDs = [id]
        } else {
            selectedPhotoIDs.removeAll()
        }
    }

    /// Gauche de la barre vitrée : dimensions de la photo en mode Développement (le changement de mode est dans les icônes hors barre).
    @ViewBuilder
    private var leadingTopChromeCluster: some View {
        if workspaceMode == .develop, let photo = selectedPhoto {
            Text("\(photo.pixelWidth)×\(photo.pixelHeight)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 72, alignment: .leading)
                .lineLimit(1)
                .frame(height: 36, alignment: .center)
        }
    }

    private var trailingExportButton: some View {
        Group {
            if isExporting {
                exportProgressIndicator
            } else {
                Button {
                    showExportSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(exportTargets.isEmpty ? Color.secondary : Color.primary)
                        .frame(width: topChromeBarHeight, height: topChromeBarHeight)
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(WorkspaceChromeOuterIconButtonStyle(cornerRadius: 10))
                .disabled(exportTargets.isEmpty)
                .help(String(localized: exportTargets.isEmpty
                                ? "batch.export.help_empty"
                                : "batch.export.help"))
                .accessibilityLabel(Text("batch.export.title"))
            }
        }
        .frame(width: topChromeBarHeight, height: topChromeBarHeight, alignment: .center)
    }

    /// Indicateur circulaire qui remplace l'icône export pendant un lot. Cliquable pour annuler.
    private var exportProgressIndicator: some View {
        Button {
            cancelExport()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.18), lineWidth: 2.4)
                Circle()
                    .trim(from: 0, to: max(0.02, exportProgress))
                    .stroke(ZenithTheme.accent, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.18), value: exportProgress)
                Text("\(Int((exportProgress * 100).rounded()))")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.primary)
            }
            .frame(width: 30, height: 30)
            .frame(width: topChromeBarHeight, height: topChromeBarHeight)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(String(localized: "batch.export.cancel_help"))
        .accessibilityLabel(Text("batch.export.cancel_help"))
    }

    /// Photos cibles pour l'export : multi-sélection si > 0, sinon photo focus, sinon vide.
    private var exportTargets: [PhotoRecord] {
        let multi = selectedPhotos
        if !multi.isEmpty { return multi }
        return [selectedPhoto].compactMap { $0 }
    }

    private func startExport(
        photos: [PhotoRecord],
        to destinationDirectory: URL,
        format: BatchExportFormat,
        quality: CGFloat
    ) {
        guard !isExporting, !photos.isEmpty else { return }
        isExporting = true
        exportProgress = 0
        exportTask = Task { @MainActor in
            do {
                try await BatchExporter.export(
                    photos: photos,
                    to: destinationDirectory,
                    format: format,
                    quality: quality,
                    onProgress: { progress in
                        exportProgress = progress
                    }
                )
            } catch is CancellationError {
                // L'utilisateur a annulé : message silencieux.
            } catch {
                photoImportFailureMessage = error.localizedDescription
            }
            isExporting = false
            exportProgress = 0
            exportTask = nil
        }
    }

    private func cancelExport() {
        exportTask?.cancel()
    }

    /// Curseur zoom (échelle logarithmique), pourcentage éditable, centrage et retour à 100 %.
    private var previewZoomSliderCluster: some View {
        HStack(spacing: 8) {
            Slider(value: previewZoomLogBinding, in: log(Double(previewZoomMin)) ... log(Double(previewZoomMax)))
                .controlSize(.small)
                .frame(width: 110)

            zoomPercentField

            Button {
                NotificationCenter.default.post(name: .zenithCenterPreview, object: nil)
            } label: {
                Image(systemName: "dot.viewfinder")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "preview.center"))
            .accessibilityLabel(Text("preview.center"))

            Button {
                previewZoomScale = 1.0
            } label: {
                Image(systemName: "1.magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(abs(previewZoomScale - 1.0) < 0.000_1)
            .help(String(localized: "preview.zoom.reset"))
        }
    }

    /// Champ éditable du pourcentage de zoom : saisir une valeur libre (5 → 1600).
    private var zoomPercentField: some View {
        HStack(spacing: 1) {
            TextField("", text: $zoomFieldText)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
                .frame(width: 36)
                .focused($zoomFieldFocused)
                .onSubmit { commitZoomFieldText() }
                .onChange(of: zoomFieldFocused) { _, focused in
                    if focused {
                        syncZoomFieldText()
                    } else {
                        commitZoomFieldText()
                    }
                }
                .onChange(of: previewZoomScale) { _, _ in
                    if !zoomFieldFocused { syncZoomFieldText() }
                }
                .onAppear { syncZoomFieldText() }
            Text("%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(zoomFieldFocused ? 0.10 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(zoomFieldFocused ? 0.25 : 0.10), lineWidth: 1)
        )
        .help(String(localized: "preview.zoom.field_help"))
    }

    private func syncZoomFieldText() {
        zoomFieldText = "\(Int((previewZoomScale * 100).rounded()))"
    }

    private func commitZoomFieldText() {
        let trimmed = zoomFieldText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "%", with: "")
        if let parsed = Double(trimmed) {
            let clamped = min(max(parsed, Double(previewZoomMin) * 100), Double(previewZoomMax) * 100)
            previewZoomScale = CGFloat(clamped / 100)
        }
        syncZoomFieldText()
    }

    private var previewZoomLogBinding: Binding<Double> {
        let lo = log(Double(previewZoomMin))
        let hi = log(Double(previewZoomMax))
        return Binding(
            get: {
                let z = Double(min(max(previewZoomScale, previewZoomMin), previewZoomMax))
                return log(z).clamped(to: lo ... hi)
            },
            set: { logVal in
                let z = exp(logVal.clamped(to: lo ... hi))
                previewZoomScale = CGFloat(min(max(z, Double(previewZoomMin)), Double(previewZoomMax)))
            }
        )
    }

    @ViewBuilder
    private var rightGlassSidebar: some View {
        VStack(spacing: 0) {
            if let photo = selectedPhoto {
                PhotoHistogramView(photo: photo)
                DevelopToolStrip(photo: photo, activeTool: $developCanvasTool)
                Text("develop.column.adjustments")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, ZenithTheme.sidebarColumnHorizontalPadding)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
                ScrollViewReader { proxy in
                    ScrollView {
                        DevelopPanel(photo: photo)
                            .padding(.horizontal, ZenithTheme.sidebarColumnHorizontalPadding)
                    }
                    .scrollIndicators(.automatic)
                    .onReceive(NotificationCenter.default.publisher(for: .zenithScrollDevelopGrainNoise)) { _ in
                        withAnimation(.snappy(duration: 0.25)) {
                            proxy.scrollTo("grainNoiseCard", anchor: .top)
                        }
                    }
                }
                Divider()
                    .opacity(0.25)
                DevelopPanelFooter(
                    compareOriginal: $developCompareOriginal,
                    onResetAll: {
                        guard let photo = selectedPhoto else { return }
                        photo.resetDevelopToNeutral()
                        try? modelContext.save()
                    }
                )
                .padding(.horizontal, ZenithTheme.sidebarColumnHorizontalPadding)
                .padding(.vertical, ZenithTheme.sidebarColumnHorizontalPadding)
            } else {
                Spacer(minLength: 0)
                Text("workspace.select_for_develop")
                    .foregroundStyle(.secondary)
                    .padding(ZenithTheme.sidebarColumnHorizontalPadding)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZenithTheme.liquidSidebarGlass(ZenithTheme.sidebarFloatingGlassShape)
        }
        .clipShape(ZenithTheme.sidebarFloatingGlassShape)
    }

    private var libraryMetadataSidebar: some View {
        LibraryMetadataSidebar(photo: selectedPhoto)
    }

    private func onWorkspaceAppear() {
        do {
            if let lib = try CatalogBootstrap.seedIfNeeded(modelContext: modelContext), sidebarSelection == nil {
                sidebarSelection = .collection(lib)
            }
        } catch {
            photoImportFailureMessage = error.localizedDescription
        }
        if sidebarSelection == nil {
            if let lib = CatalogBootstrap.libraryCollectionID(from: collections) {
                sidebarSelection = .collection(lib)
            } else if let first = collections.first?.collectionUUID {
                sidebarSelection = .collection(first)
            }
        }
        focusWorkspace = true
        validatePersistedPhotoSelection()
    }

    /// Conserve uniquement les IDs de la multi-sélection qui restent visibles dans le filtrage courant.
    /// Évite que des actions groupées s’appliquent à des photos invisibles après un changement de collection.
    private func pruneMultiSelectionToVisible() {
        guard !selectedPhotoIDs.isEmpty else { return }
        let visibleIDs = Set(filteredPhotos.map(\.id))
        let pruned = selectedPhotoIDs.intersection(visibleIDs)
        if pruned.count != selectedPhotoIDs.count {
            selectedPhotoIDs = pruned
        }
    }

    private func validatePersistedPhotoSelection() {
        guard !persistedPhotoID.isEmpty else { return }
        guard let id = UUID(uuidString: persistedPhotoID) else {
            persistedPhotoID = ""
            return
        }
        if !photos.contains(where: { $0.id == id }) {
            persistedPhotoID = ""
        }
    }

    private func applyHealTapFromPreview(x: CGFloat, y: CGFloat) {
        guard let photo = selectedPhoto else { return }
        var s = photo.developSettings
        s.healNormX = Double(min(max(x, 0), 1))
        s.healNormY = Double(min(max(y, 0), 1))
        if s.healRadiusPx < 8 {
            s.healRadiusPx = 36
        }
        photo.applyDevelopSettings(s)
        try? modelContext.save()
    }

    /// Découpe pour le typage du compilateur (SwiftUI).
    private var workspaceRoot: some View {
        workspaceChrome
            .background(ZenithTheme.pageBackground)
            // Dessine sous la zone titre : avec `titlebarAppearsTransparent`, l’aperçu remplit la bande au lieu d’un gris système.
            .ignoresSafeArea(.container, edges: .top)
            .tint(ZenithTheme.accent)
            .preferredColorScheme(.dark)
            .environment(\.dynamicTypeSize, resolvedDynamicType)
    }

    private var workspaceWithLifecycle: some View {
        workspaceRoot
            .onAppear { onWorkspaceAppear() }
            .onChange(of: persistedPhotoID) { _, _ in
                previewZoomScale = 1.0
                developCanvasTool = .none
            }
            .onChange(of: photos.count) { _, _ in
                validatePersistedPhotoSelection()
                pruneMultiSelectionToVisible()
            }
            .onChange(of: sidebarSelection) { _, _ in
                pruneMultiSelectionToVisible()
            }
            .onChange(of: collections.count) { _, _ in
                if sidebarSelection == nil {
                    if let lib = CatalogBootstrap.libraryCollectionID(from: collections) {
                        sidebarSelection = .collection(lib)
                    } else if let first = collections.first?.collectionUUID {
                        sidebarSelection = .collection(first)
                    }
                }
            }
    }

    private var workspaceWithNotifications: some View {
        workspaceWithLifecycle
            .onReceive(NotificationCenter.default.publisher(for: .zenithImportPhotos)) { _ in runImport() }
            .onReceive(NotificationCenter.default.publisher(for: .zenithImportLightroomCatalog)) { _ in runLightroomImport() }
            .onReceive(NotificationCenter.default.publisher(for: .zenithBatchExport)) { _ in showExportSheet = true }
            .onReceive(NotificationCenter.default.publisher(for: .zenithInviteCollaborator)) { _ in showInviteSheet = true }
            .onReceive(NotificationCenter.default.publisher(for: .zenithToggleFullScreen)) { _ in
                NSApp.keyWindow?.toggleFullScreen(nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: .zenithUndoDevelop)) { _ in
                guard let photo = selectedPhoto, photo.undoDevelop() else { return }
                try? modelContext.save()
            }
            .onReceive(NotificationCenter.default.publisher(for: .zenithRedoDevelop)) { _ in
                guard let photo = selectedPhoto, photo.redoDevelop() else { return }
                try? modelContext.save()
            }
            .onReceive(NotificationCenter.default.publisher(for: .zenithCopyDevelop)) { _ in
                guard let photo = selectedPhoto else { return }
                DevelopClipboard.copy(photo.developSettings)
            }
            .onReceive(NotificationCenter.default.publisher(for: .zenithPasteDevelop)) { _ in
                guard let photo = selectedPhoto, let pasted = DevelopClipboard.paste() else { return }
                photo.applyDevelopSettings(pasted)
                try? modelContext.save()
            }
            .onReceive(NotificationCenter.default.publisher(for: .zenithSyncPresetToSelection)) { _ in
                syncDevelopToGrid()
            }
            .onReceive(NotificationCenter.default.publisher(for: .zenithExportCatalogBackup)) { _ in
                runExportCatalogBackup()
            }
            .onReceive(NotificationCenter.default.publisher(for: .zenithLinkCloudFolder)) { _ in
                runLinkCloudFolder()
            }
            .onReceive(NotificationCenter.default.publisher(for: .zenithShowCatalogOverview)) { _ in
                persistedWorkspaceModeRaw = WorkspaceTab.catalog.rawValue
            }
    }

    var body: some View {
        workspaceWithNotifications
            .alert("import.alert.title", isPresented: isPhotoImportFailurePresented) {
                Button("import.alert.ok", role: .cancel) { photoImportFailureMessage = nil }
            } message: {
                Text(photoImportFailureMessage ?? "")
            }
            .sheet(isPresented: $showInviteSheet) {
                CollaborationInviteSheet()
            }
            .sheet(isPresented: $showExportSheet) {
                BatchExportSheet(
                    photos: exportTargets,
                    onStart: { photos, url, format, quality in
                        startExport(photos: photos, to: url, format: format, quality: quality)
                    }
                )
            }
            .sheet(isPresented: $showNewCollectionSheet) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("collection.new.headline")
                        .font(.headline)
                    TextField(
                        String(localized: "collection.new.placeholder"),
                        text: $newCollectionName
                    )
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submitNewCollectionSheet() }

                    HStack {
                        Spacer()
                        Button("common.cancel", role: .cancel) {
                            cancelNewCollectionSheet()
                        }
                        .keyboardShortcut(.cancelAction)

                        Button("collection.new.create") {
                            submitNewCollectionSheet()
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(20)
                .frame(minWidth: 320)
                .background(ZenithTheme.pageBackground)
            }
            .photoTriageKeyboard(
                photos: selectedPhotos,
                modelContext: modelContext,
                onDeleteRequested: {
                    let ids = selectedPhotoIDs.isEmpty
                        ? Set([selectedPhotoID].compactMap { $0 })
                        : selectedPhotoIDs
                    if !ids.isEmpty {
                        requestPhotoDeletion(ids: ids)
                    }
                }
            )
            .confirmationDialog(
                deletionDialogTitle,
                isPresented: pendingPhotoDeletionPresented,
                presenting: pendingPhotoDeletion
            ) { request in
                Button("library.delete.catalog_only", role: .destructive) {
                    performPhotoDeletion(request: request, moveSourceToTrash: false)
                }
                Button("library.delete.move_to_trash", role: .destructive) {
                    performPhotoDeletion(request: request, moveSourceToTrash: true)
                }
                Button("library.delete.cancel", role: .cancel) {
                    pendingPhotoDeletion = nil
                }
            } message: { request in
                Text(deletionDialogMessage(for: request))
            }
            .focusable()
            .focused($focusWorkspace)
    }

    private var deletionDialogTitle: LocalizedStringKey {
        guard let pending = pendingPhotoDeletion else { return "library.delete.title" }
        return pending.photoIDs.count > 1
            ? "library.delete.title_multi"
            : "library.delete.title"
    }

    private var pendingPhotoDeletionPresented: Binding<Bool> {
        Binding(
            get: { pendingPhotoDeletion != nil },
            set: { isPresented in
                if !isPresented { pendingPhotoDeletion = nil }
            }
        )
    }

    private func deletionDialogMessage(for request: PendingPhotoDeletion) -> String {
        if request.photoIDs.count > 1 {
            let format = String(localized: "library.delete.message_multi_format")
            return String(format: format, locale: .current, request.photoIDs.count)
        }
        if let firstID = request.photoIDs.first,
           let photo = photos.first(where: { $0.id == firstID }) {
            let format = String(localized: "library.delete.message_single_format")
            return String(format: format, locale: .current, photo.filename)
        }
        return String(localized: "library.delete.message_single_fallback")
    }

    private func requestPhotoDeletion(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        pendingPhotoDeletion = PendingPhotoDeletion(photoIDs: ids)
    }

    private func performPhotoDeletion(request: PendingPhotoDeletion, moveSourceToTrash: Bool) {
        let toDelete = photos.filter { request.photoIDs.contains($0.id) }
        var trashErrors: [String] = []

        if moveSourceToTrash {
            for photo in toDelete {
                guard let url = try? photo.resolvedURL() else {
                    trashErrors.append(photo.filename + " · " + String(localized: "library.delete.error.unresolved"))
                    continue
                }
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                do {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                } catch {
                    trashErrors.append("\(photo.filename) · \(error.localizedDescription)")
                }
            }
        }

        for photo in toDelete {
            modelContext.delete(photo)
        }

        selectedPhotoIDs.subtract(request.photoIDs)
        if let primary = selectedPhotoID, request.photoIDs.contains(primary) {
            persistedPhotoID = selectedPhotoIDs.first?.uuidString ?? ""
        }

        try? modelContext.save()
        pendingPhotoDeletion = nil

        if !trashErrors.isEmpty {
            photoImportFailureMessage = trashErrors.joined(separator: "\n")
        }
    }

    /// Cibles d'une action de notation/drapeau : la multi-sélection si présente, sinon la photo focus.
    private var ratingTargets: [PhotoRecord] {
        let multi = selectedPhotos
        if !multi.isEmpty { return multi }
        return [selectedPhoto].compactMap { $0 }
    }

    private func starPicker(for photo: PhotoRecord) -> some View {
        HStack(spacing: 2) {
            ForEach(1 ... 5, id: \.self) { n in
                Button {
                    let targets = ratingTargets
                    for t in targets { t.rating = n }
                    try? modelContext.save()
                } label: {
                    Image(systemName: n <= photo.rating ? "star.fill" : "star")
                        .font(.system(size: 15))
                        .foregroundStyle(n <= photo.rating ? .yellow : .secondary)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help(String(format: String(localized: "toolbar.stars_help"), n))
            }
            Button {
                let targets = ratingTargets
                for t in targets { t.rating = 0 }
                try? modelContext.save()
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 15))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(String(localized: "toolbar.reset_rating"))
        }
        .fixedSize()
        .accessibilityLabel(String(localized: "toolbar.stars_a11y"))
    }

    private func flagPicker(for photo: PhotoRecord) -> some View {
        HStack(spacing: 8) {
            Button {
                let targets = ratingTargets
                let next: PhotoPickFlag = photo.flag == .pick ? .none : .pick
                for t in targets { t.flag = next }
                try? modelContext.save()
            } label: {
                Image(systemName: "flag.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(photo.flag == .pick ? Color.green : Color.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(String(localized: "toolbar.flag_pick"))

            Button {
                let targets = ratingTargets
                let next: PhotoPickFlag = photo.flag == .reject ? .none : .reject
                for t in targets { t.flag = next }
                try? modelContext.save()
            } label: {
                Image(systemName: "flag.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(photo.flag == .reject ? Color.red : Color.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(String(localized: "toolbar.flag_reject"))
        }
        .fixedSize()
    }

    private var filteredPhotos: [PhotoRecord] {
        photoSubset(for: sidebarSelection)
    }

    /// Photos visibles pour une sélection de barre latérale (même logique que `filteredPhotos`).
    private func photoSubset(for selection: SidebarSelection?) -> [PhotoRecord] {
        switch selection {
        case nil:
            return photos
        case .some(.collection(let sid)):
            return photos.filter { $0.collectionID == sid }
        case .some(.monthYear(let year, let month)):
            let cal = Calendar.current
            return photos.filter {
                let c = cal.dateComponents([.year, .month], from: $0.addedAt)
                return c.year == year && c.month == month
            }
        }
    }

    /// En mode Développement : après clic sur une entrée de la sidebar, conserve la photo courante si elle
    /// est encore dans ce dossier (dernière vue valide) ; sinon sélectionne la dernière photo du jeu filtré
    /// (même ordre que la pellicule / la grille).
    private func selectPhotoForDevelopSidebar(_ selection: SidebarSelection?) {
        let subset = photoSubset(for: selection)
        guard !subset.isEmpty else {
            persistedPhotoID = ""
            selectedPhotoIDs = []
            return
        }
        if let current = selectedPhotoID, subset.contains(where: { $0.id == current }) {
            persistedPhotoID = current.uuidString
            selectedPhotoIDs = [current]
            return
        }
        if let id = subset.last?.id {
            persistedPhotoID = id.uuidString
            selectedPhotoIDs = [id]
        }
    }

    private var importDestinationCollectionID: UUID? {
        switch sidebarSelection {
        case .some(.collection(let id)):
            return id
        case .some(.monthYear), .none:
            return CatalogBootstrap.libraryCollectionID(from: collections) ?? collections.first?.collectionUUID
        }
    }

    private var selectedPhoto: PhotoRecord? {
        photos.first { $0.id == selectedPhotoID }
    }

    /// Import via `NSOpenPanel` (action explicite « Importer des photos »).
    /// Pour une session par glisser/déposer, voir `runImport(droppedURLs:)`.
    private func runImport() {
        do {
            let summary = try PhotoImporter.importPhotos(
                modelContext: modelContext,
                collectionID: importDestinationCollectionID,
                currentCount: photos.count
            )
            handleImportSummary(summary)
        } catch {
            photoImportFailureMessage = error.localizedDescription
        }
    }

    /// Import des références de fichiers depuis un catalogue Lightroom Classic (`.lrcat`) dans le catalogue Zenith courant.
    private func runLightroomImport() {
        do {
            let summary = try LightroomCatalogImporter.importViaOpenPanel(
                modelContext: modelContext,
                currentPhotoCount: photos.count,
                collections: collections
            )
            handleImportSummary(summary)
        } catch {
            photoImportFailureMessage = error.localizedDescription
        }
    }

    /// Import déclenché par un drop Finder dans la grille bibliothèque : on traite les URL déjà résolues.
    private func runImport(droppedURLs urls: [URL]) {
        do {
            let summary = try PhotoImporter.importPhotos(
                from: urls,
                modelContext: modelContext,
                collectionID: importDestinationCollectionID,
                currentCount: photos.count,
                requireSecurityScope: false
            )
            handleImportSummary(summary)
        } catch {
            photoImportFailureMessage = error.localizedDescription
        }
    }

    /// Met à jour la sélection après import et expose un avertissement non bloquant si quelques fichiers
    /// ont été ignorés (ex. format non supporté, permission refusée).
    private func handleImportSummary(_ summary: PhotoImportSummary) {
        if selectedPhotoID == nil, let first = filteredPhotos.first?.id {
            persistedPhotoID = first.uuidString
        }
        if summary.imported > 0, summary.failed > 0, let reason = summary.firstFailureReason {
            let format = String(localized: "import.warning.partial_format")
            photoImportFailureMessage = String(format: format, locale: .current, summary.imported, summary.failed, reason)
        }
    }

    private func addUserCollection(named name: String) {
        guard let parent = collections.first(where: { $0.name == "Collections" })?.collectionUUID else { return }
        let nextIndex = (collections.filter { $0.parentID == parent }.map(\.sortIndex).max() ?? 0) + 1
        let c = CollectionRecord(name: name, parentID: parent, sortIndex: nextIndex)
        modelContext.insert(c)
        try? modelContext.save()
        sidebarSelection = .collection(c.collectionUUID)
        /// Si l’utilisateur a ouvert la modale via « Déplacer vers → Nouvelle collection »,
        /// on assigne immédiatement les photos en attente à la collection fraîchement créée.
        if !pendingMoveIDs.isEmpty {
            movePhotos(ids: pendingMoveIDs, toCollection: c.collectionUUID)
            pendingMoveIDs = []
        }
        if workspaceMode != .library {
            persistedWorkspaceModeRaw = WorkspaceTab.library.rawValue
        }
    }

    /// Validation de la feuille de création : crée la collection si le nom n’est pas vide,
    /// puis ferme proprement la modale en vidant le champ.
    private func submitNewCollectionSheet() {
        let trimmed = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        addUserCollection(named: trimmed)
        newCollectionName = ""
        showNewCollectionSheet = false
    }

    /// Annulation explicite (bouton Annuler ou ⎋) : ne crée rien, vide le champ et ferme la modale.
    /// Vide aussi `pendingMoveIDs` pour ne pas réassigner par mégarde lors d’une prochaine création.
    private func cancelNewCollectionSheet() {
        newCollectionName = ""
        pendingMoveIDs = []
        showNewCollectionSheet = false
    }

    /// Cibles affichées dans le menu contextuel « Déplacer vers ». On reproduit la hiérarchie
    /// présentée dans la sidebar (enfants du dossier système « Collections ») triés par nom.
    /// Les dossiers système (Bibliothèque, Collections) sont exclus pour éviter les doublons.
    private var userCollectionTargets: [LibraryCollectionTarget] {
        let collectionsRootID = collections.first { $0.name == "Collections" && $0.parentID == nil }?.collectionUUID
        guard let collectionsRootID else { return [] }

        func childrenSorted(of parent: UUID) -> [CollectionRecord] {
            collections
                .filter { $0.parentID == parent }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }

        var rows: [LibraryCollectionTarget] = []
        func walk(_ node: CollectionRecord, depth: Int) {
            rows.append(LibraryCollectionTarget(id: node.collectionUUID, name: node.name, depth: depth))
            for child in childrenSorted(of: node.collectionUUID) {
                walk(child, depth: depth + 1)
            }
        }
        for root in childrenSorted(of: collectionsRootID) {
            walk(root, depth: 0)
        }
        return rows
    }

    /// Déplace un ensemble de photos vers une collection cible : met à jour `collectionID` puis sauvegarde.
    /// On ne vide pas la sélection : si l’utilisateur navigue vers la collection cible il retrouve ses photos.
    private func movePhotos(ids: Set<UUID>, toCollection collectionID: UUID) {
        guard !ids.isEmpty else { return }
        let targets = photos.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }
        for photo in targets {
            photo.collectionID = collectionID
        }
        try? modelContext.save()
    }

    /// Demande la création d’une nouvelle collection avec assignation immédiate des photos cibles.
    /// On stocke les IDs dans `pendingMoveIDs` ; la modale standard de nouvelle collection se charge du nommage.
    private func requestMoveToNewCollection(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        pendingMoveIDs = ids
        newCollectionName = ""
        showNewCollectionSheet = true
    }

    private func runExportCatalogBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Zenith-catalog-backup.json"
        panel.title = String(localized: "backup.save.title")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CatalogBackupExporter.writeJSONSnapshot(to: url, modelContext: modelContext)
        } catch {
            photoImportFailureMessage = error.localizedDescription
        }
    }

    private func runLinkCloudFolder() {
        guard let url = CloudFolderBookmark.chooseFolderPanel() else { return }
        do {
            try CloudFolderBookmark.saveBookmark(from: url)
        } catch {
            photoImportFailureMessage = error.localizedDescription
        }
    }

    private func syncDevelopToGrid() {
        guard let source = selectedPhoto else { return }
        let settings = source.developSettings
        guard let encoded = try? settings.encoded() else { return }
        for photo in filteredPhotos {
            photo.developBlob = encoded
            photo.undoStackBlob = DevelopUndoStacks.emptyEncodedData
        }
        try? modelContext.save()
    }
}

/// État UI transitoire pour la confirmation de suppression : l'utilisateur choisit ensuite « catalogue uniquement » ou « + corbeille ».
struct PendingPhotoDeletion: Identifiable, Hashable {
    let id = UUID()
    let photoIDs: Set<UUID>
}

/// Style d’icône avec cadre fixe : évite le déplacement des boutons `.borderless` natifs sur macOS au pressed/hover.
private struct WorkspaceChromeIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.14) : Color.primary.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

/// Variante externe (hors barre) reprenant le verre des colonnes latérales.
private struct WorkspaceChromeOuterIconButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                ZenithTheme.liquidSidebarGlass(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(configuration.isPressed ? 0.24 : 0.14), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private struct CollaborationInviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("zenith.collaborationRole") private var collaborationRoleRaw = "edit"
    @AppStorage("zenith.collaborationEnabled") private var collaborationEnabled = false

    @State private var email = ""
    @State private var password = ""
    @State private var otpCode = ""

    private enum CollaborationRole: String, CaseIterable, Identifiable {
        case read
        case edit
        var id: String { rawValue }
    }

    private var selectedRole: CollaborationRole {
        CollaborationRole(rawValue: collaborationRoleRaw) ?? .edit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("collaboration.invite.title")
                .font(.title2.bold())
            Text("collaboration.invite.body")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("collaboration.invite.email", text: $email)
                .textFieldStyle(.roundedBorder)
            SecureField("collaboration.invite.password", text: $password)
                .textFieldStyle(.roundedBorder)
            TextField("collaboration.invite.otp", text: $otpCode)
                .textFieldStyle(.roundedBorder)
            Picker("collaboration.invite.role_picker", selection: $collaborationRoleRaw) {
                Text("collaboration.role.read").tag(CollaborationRole.read.rawValue)
                Text("collaboration.role.edit").tag(CollaborationRole.edit.rawValue)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(Text("collaboration.invite.role_picker"))
            Text(
                selectedRole == .edit
                    ? String(localized: "collaboration.invite.hint_edit")
                    : String(localized: "collaboration.invite.hint_read")
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("collaboration.invite.cancel") { dismiss() }
                Button("collaboration.invite.send") {
                    collaborationEnabled = true
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
        .background(ZenithTheme.pageBackground)
    }
}
