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
    @AppStorage("zenith.workspaceMode") private var persistedWorkspaceModeRaw = WorkspaceHierarchyMode.library.rawValue
    @AppStorage("zenith.lastSelectedPhotoID") private var persistedPhotoID = ""

    @State private var sidebarSelection: SidebarSelection?
    @State private var showInviteSheet = false
    @State private var showExportSheet = false
    @State private var photoImportFailureMessage: String?
    @State private var developCompareOriginal = false
    @State private var previewZoomScale: CGFloat = 1.0
    @State private var developCanvasTool: DevelopCanvasTool = .none
    @State private var showNewCollectionSheet = false
    @State private var showCatalogSheet = false
    @State private var newCollectionName = ""
    @FocusState private var focusWorkspace: Bool

    private var workspaceMode: WorkspaceHierarchyMode {
        WorkspaceHierarchyMode(rawValue: persistedWorkspaceModeRaw) ?? .library
    }

    private var workspaceModeBinding: Binding<WorkspaceHierarchyMode> {
        Binding(
            get: { WorkspaceHierarchyMode(rawValue: persistedWorkspaceModeRaw) ?? .library },
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
                } else {
                    persistedPhotoID = ""
                }
            }
        )
    }

    private let previewZoomMin: CGFloat = 0.05
    private let previewZoomMax: CGFloat = 16

    private let leftSidebarWidth: CGFloat = 260
    /// Colonne gauche élargie en développement (navigateur + préréglages).
    private let developLeftSidebarWidth: CGFloat = 282
    private let developRightSidebarWidth: CGFloat = 340

    private var effectiveLeftSidebarWidth: CGFloat {
        workspaceMode == .develop ? developLeftSidebarWidth : leftSidebarWidth
    }
    /// Marge verticale au-dessus et en dessous des barres latérales vitrées.
    private let sidebarVerticalInset: CGFloat = 16
    /// Hauteur de la barre horizontale transparente (zoom, export) au-dessus des colonnes.
    private let topChromeBarHeight: CGFloat = 48
    /// Décalage sous les boutons fermer / réduire / zoom une fois le contenu étendu sous la barre titre.
    private let windowControlsTopInset: CGFloat = 28
    /// Marge horizontale entre le bord de la fenêtre et la barre du haut (verre).
    private let topChromeHorizontalInset: CGFloat = 16

    /// Hauteur de la bande de fond sous la barre chrome (alignée sur l’overlay) : même luminance que la page pour que le verre ne suive pas l’image.
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

    /// Bibliothèque (grille + notation) · Développement (post-production). Le catalogue est dans Fichier.
    @ViewBuilder
    private var mainWorkspaceCanvas: some View {
        switch workspaceMode {
        case .library:
            LibraryGridView(photos: filteredPhotos, selectedPhotoID: selectedPhotoIDBinding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .develop:
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
        }
    }

    /// Canevas principal ; barre latérale gauche (navigation) ; droite réservée au développement.
    @ViewBuilder
    private var workspaceChrome: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                mainWorkspaceCanvas

                VStack(spacing: 0) {
                    ZenithTheme.pageBackground
                        .frame(height: topChromeBackingBandHeight)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)

                HStack(alignment: .top, spacing: 0) {
                    if leftSidebarVisible {
                        leftGlassSidebar
                            .frame(width: effectiveLeftSidebarWidth)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    Spacer(minLength: 0)
                        .allowsHitTesting(false)

                    if workspaceMode == .develop {
                        rightGlassSidebar
                            .frame(width: developRightSidebarWidth)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
                .padding(.top, windowControlsTopInset + topChromeBarHeight + sidebarVerticalInset)
                .padding(.bottom, sidebarVerticalInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .animation(.snappy(duration: 0.22), value: leftSidebarVisible)
            }
            .overlay(alignment: .top) {
                topWorkspaceChromeBar
                    .padding(.horizontal, topChromeHorizontalInset)
                    .padding(.top, windowControlsTopInset)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if workspaceMode == .develop {
                FilmstripView(photos: filteredPhotos, selection: selectedPhotoIDBinding)
                    .zIndex(2)
            }
        }
        .frame(minWidth: 900, minHeight: 500)
    }

    @ViewBuilder
    private var developAuxiliaryColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let photo = selectedPhoto {
                DevelopNavigatorThumb(photo: photo)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                PresetsPanel(photo: photo, compact: true)
                developCopyPasteToolbar
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            } else {
                Spacer(minLength: 0)
                Text("workspace.select_for_develop")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding(12)
                Spacer(minLength: 0)
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

    private var collectionsSidebarNavigation: some View {
        NavigationStack {
            CollectionsSidebar(
                collections: collections,
                photos: photos,
                selection: $sidebarSelection,
                onAddCollection: { showNewCollectionSheet = true }
            )
        }
    }

    private var workspaceModeSidebarPicker: some View {
        Picker("", selection: workspaceModeBinding) {
            Text("workspace.mode.library").tag(WorkspaceHierarchyMode.library)
            Text("workspace.mode.develop").tag(WorkspaceHierarchyMode.develop)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel(Text("workspace.mode.picker_a11y"))
    }

    @ViewBuilder
    private var leftGlassSidebar: some View {
        VStack(spacing: 0) {
            workspaceModeSidebarPicker
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 6)
            Divider()
                .opacity(0.28)
            Group {
                if workspaceMode == .develop {
                    if collaborationEnabled {
                        VSplitView {
                            VSplitView {
                                collectionsSidebarNavigation
                                    .frame(minHeight: 100, idealHeight: 200)
                                developAuxiliaryColumn
                            }
                            .frame(minHeight: 260)

                            ChatPanel(
                                photos: filteredPhotos,
                                selectedPhotoID: selectedPhotoID
                            )
                            .frame(minHeight: 140)
                        }
                    } else {
                        VSplitView {
                            collectionsSidebarNavigation
                                .frame(minHeight: 100, idealHeight: 200)
                            developAuxiliaryColumn
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
            ZenithTheme.liquidSidebarGlass(ZenithTheme.sidebarGlassShapeLeading)
        }
        .clipShape(ZenithTheme.sidebarGlassShapeLeading)
    }

    /// Barre du haut : gauche (sidebar + drapeaux / dimensions en développement), centre (notation + zoom), export à droite.
    private var topWorkspaceChromeBar: some View {
        HStack(alignment: .center, spacing: 10) {
            leadingTopChromeCluster

            Spacer(minLength: 8)

            centerTopChromeCluster
                .frame(maxWidth: .infinity)

            Spacer(minLength: 8)

            trailingExportButton
        }
        .padding(.horizontal, 12)
        .frame(height: topChromeBarHeight)
        .background {
            ZenithTheme.liquidSidebarGlass(ZenithTheme.topChromeGlassShape)
        }
        .clipShape(ZenithTheme.topChromeGlassShape)
    }

    /// Notation (étoiles) et zoom regroupés au centre de la barre.
    private var centerTopChromeCluster: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            if let photo = selectedPhoto {
                starPicker(for: photo)
            }
            if workspaceMode == .develop {
                previewZoomSliderCluster
                    .frame(maxWidth: 320)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 36, alignment: .center)
    }

    /// Gauche de la barre du haut : masquage sidebar ; drapeaux et dimensions en mode développement.
    private var leadingTopChromeCluster: some View {
        HStack(alignment: .center, spacing: 8) {
            if leftSidebarVisible {
                sidebarHideButton
            } else {
                sidebarShowButton
            }

            if let photo = selectedPhoto, workspaceMode == .develop {
                Divider()
                    .frame(height: 22)
                    .opacity(0.35)

                flagPicker(for: photo)
                Text("\(photo.pixelWidth)×\(photo.pixelHeight)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 72, alignment: .leading)
                    .lineLimit(1)
            }
        }
        .frame(height: 36, alignment: .center)
    }

    private var trailingExportButton: some View {
        Button {
            showExportSheet = true
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(WorkspaceChromeIconButtonStyle())
        .help(String(localized: "batch.export.title"))
        .accessibilityLabel(Text("batch.export.title"))
        .frame(height: 36, alignment: .center)
    }

    private var sidebarHideButton: some View {
        Button {
            leftSidebarVisible = false
        } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(WorkspaceChromeIconButtonStyle())
        .help(String(localized: "workspace.sidebar.hide"))
        .accessibilityLabel(Text("workspace.sidebar.hide"))
    }

    private var sidebarShowButton: some View {
        Button {
            leftSidebarVisible = true
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(WorkspaceChromeIconButtonStyle())
        .help(String(localized: "workspace.sidebar.show"))
        .accessibilityLabel(Text("workspace.sidebar.show"))
    }

    /// Curseur zoom (échelle logarithmique) et réinitialisation, centrés dans la fenêtre.
    private var previewZoomSliderCluster: some View {
        HStack(spacing: 10) {
            Slider(value: previewZoomLogBinding, in: log(Double(previewZoomMin)) ... log(Double(previewZoomMax)))
                .controlSize(.small)

            Text("\(Int((previewZoomScale * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
                .lineLimit(1)

            Button {
                previewZoomScale = 1.0
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(abs(previewZoomScale - 1.0) < 0.000_1)
            .help(String(localized: "preview.zoom.reset"))
        }
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
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
                ScrollViewReader { proxy in
                    ScrollView {
                        DevelopPanel(photo: photo)
                            .padding(.horizontal, 10)
                    }
                    .scrollIndicators(.automatic)
                    .onReceive(NotificationCenter.default.publisher(for: .zenithScrollToRemoveColor)) { _ in
                        withAnimation(.snappy(duration: 0.25)) {
                            proxy.scrollTo("removeColorCard", anchor: .top)
                        }
                    }
                }
                Divider()
                    .opacity(0.25)
                DevelopPanelFooter(compareOriginal: $developCompareOriginal) {
                    photo.resetDevelopToNeutral()
                    try? modelContext.save()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            } else {
                Spacer(minLength: 0)
                Text("workspace.select_for_develop")
                    .foregroundStyle(.secondary)
                    .padding(16)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZenithTheme.liquidSidebarGlass(ZenithTheme.sidebarGlassShapeTrailing)
        }
        .clipShape(ZenithTheme.sidebarGlassShapeTrailing)
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
                showCatalogSheet = true
            }
    }

    var body: some View {
        workspaceWithNotifications
            .alert("import.alert.title", isPresented: isPhotoImportFailurePresented) {
                Button("import.alert.ok", role: .cancel) { photoImportFailureMessage = nil }
            } message: {
                Text(photoImportFailureMessage ?? "")
            }
            .sheet(isPresented: $showCatalogSheet) {
                NavigationStack {
                    CatalogOverviewView(
                        photoCount: photos.count,
                        collectionFolderCount: collections.count,
                        onImportPhotos: { runImport() }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(ZenithTheme.pageBackground)
                    .navigationTitle(Text("catalog.overview.title"))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(String(localized: "catalog.sheet.done")) {
                                showCatalogSheet = false
                            }
                        }
                    }
                }
                .frame(minWidth: 480, minHeight: 440)
            }
            .sheet(isPresented: $showInviteSheet) {
                CollaborationInviteSheet()
            }
            .sheet(isPresented: $showExportSheet) {
                BatchExportSheet(photos: filteredPhotos)
            }
            .sheet(isPresented: $showNewCollectionSheet) {
                Form {
                    TextField("collection.new.title", text: $newCollectionName)
                    Button("collection.new.create") {
                        let trimmed = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            addUserCollection(named: trimmed)
                        }
                        newCollectionName = ""
                        showNewCollectionSheet = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding()
                .frame(minWidth: 280)
                .background(ZenithTheme.pageBackground)
            }
            .focused($focusWorkspace)
    }

    private func starPicker(for photo: PhotoRecord) -> some View {
        HStack(spacing: 2) {
            ForEach(1 ... 5, id: \.self) { n in
                Button {
                    photo.rating = n
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
                photo.rating = 0
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
                photo.flag = photo.flag == .pick ? .none : .pick
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
                photo.flag = photo.flag == .reject ? .none : .reject
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
        switch sidebarSelection {
        case .none:
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

    private func runImport() {
        do {
            try PhotoImporter.importPhotos(
                modelContext: modelContext,
                collectionID: importDestinationCollectionID,
                currentCount: photos.count
            )
            if selectedPhotoID == nil, let first = filteredPhotos.first?.id {
                persistedPhotoID = first.uuidString
            }
        } catch {
            photoImportFailureMessage = error.localizedDescription
        }
    }

    private func addUserCollection(named name: String) {
        guard let parent = collections.first(where: { $0.name == "Collections" })?.collectionUUID else { return }
        let nextIndex = (collections.filter { $0.parentID == parent }.map(\.sortIndex).max() ?? 0) + 1
        let c = CollectionRecord(name: name, parentID: parent, sortIndex: nextIndex)
        modelContext.insert(c)
        try? modelContext.save()
        sidebarSelection = .collection(c.collectionUUID)
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
