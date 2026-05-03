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

    @State private var sidebarSelection: SidebarSelection?
    @State private var selectedPhotoID: UUID?
    @State private var showInviteSheet = false
    @State private var showExportSheet = false
    @State private var photoImportFailureMessage: String?
    @State private var developCompareOriginal = false
    @State private var previewZoomScale: CGFloat = 1.0
    @State private var showNewCollectionSheet = false
    @State private var newCollectionName = ""
    @FocusState private var focusWorkspace: Bool

    private let previewZoomMin: CGFloat = 0.05
    private let previewZoomMax: CGFloat = 16

    private let leftSidebarWidth: CGFloat = 260
    private let rightSidebarWidth: CGFloat = 320

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

    /// Canevas plein écran ; barres latérales en verre par-dessus l’aperçu seul (image visible derrière).
    @ViewBuilder
    private var workspaceChrome: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                PhotoPreviewView(photo: selectedPhoto, compareOriginal: developCompareOriginal, zoomScale: $previewZoomScale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(alignment: .top, spacing: 0) {
                    if leftSidebarVisible {
                        leftGlassSidebar
                            .frame(width: leftSidebarWidth)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    Spacer(minLength: 0)
                        .allowsHitTesting(false)

                    rightGlassSidebar
                        .frame(width: rightSidebarWidth)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .animation(.snappy(duration: 0.22), value: leftSidebarVisible)

                if !leftSidebarVisible {
                    Button {
                        leftSidebarVisible = true
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 15))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .padding(.leading, 10)
                    .padding(.top, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .help(String(localized: "workspace.sidebar.show"))
                    .accessibilityLabel(Text("workspace.sidebar.show"))
                    .zIndex(3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FilmstripView(photos: filteredPhotos, selection: $selectedPhotoID)
                .zIndex(2)

            bottomChromeBar
                .zIndex(2)
        }
        .frame(minWidth: 900, minHeight: 500)
    }

    @ViewBuilder
    private var leftGlassSidebar: some View {
        VStack(spacing: 0) {
            leftSidebarHeaderBar

            Group {
                if collaborationEnabled {
                    VSplitView {
                        NavigationStack {
                            CollectionsSidebar(
                                collections: collections,
                                photos: photos,
                                selection: $sidebarSelection,
                                onAddCollection: { showNewCollectionSheet = true }
                            )
                        }
                        .frame(minHeight: 200)

                        ChatPanel(
                            photos: filteredPhotos,
                            selectedPhotoID: selectedPhotoID
                        )
                        .frame(minHeight: 160)
                    }
                } else {
                    NavigationStack {
                        CollectionsSidebar(
                            collections: collections,
                            photos: photos,
                            selection: $sidebarSelection,
                            onAddCollection: { showNewCollectionSheet = true }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZenithTheme.liquidSidebarGlass(ZenithTheme.sidebarGlassShapeLeading)
        }
        .clipped()
    }

    /// Bouton masquer la barre gauche (en haut de la colonne).
    private var leftSidebarHeaderBar: some View {
        HStack {
            Button {
                leftSidebarVisible = false
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 15))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(String(localized: "workspace.sidebar.hide"))
            .accessibilityLabel(Text("workspace.sidebar.hide"))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.clear)
    }

    @ViewBuilder
    private var rightGlassSidebar: some View {
        VStack(spacing: 0) {
            previewZoomToolbar
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.clear)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let photo = selectedPhoto {
                        PhotoHistogramView(photo: photo)
                        DevelopPanel(photo: photo, compareOriginal: $developCompareOriginal)
                        Divider().padding(.vertical, 8)
                        PresetsPanel(photo: photo)
                    } else {
                        Text("workspace.select_for_develop")
                            .foregroundStyle(.secondary)
                            .padding(16)
                    }
                }
            }
            .scrollIndicators(.automatic)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZenithTheme.liquidSidebarGlass(ZenithTheme.sidebarGlassShapeTrailing)
        }
        .clipped()
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
    }

    /// Découpe pour le typage du compilateur (SwiftUI).
    private var workspaceRoot: some View {
        workspaceChrome
            .tint(ZenithTheme.accent)
            .preferredColorScheme(.dark)
            .environment(\.dynamicTypeSize, resolvedDynamicType)
    }

    private var workspaceWithLifecycle: some View {
        workspaceRoot
            .onAppear { onWorkspaceAppear() }
            .onChange(of: selectedPhotoID) { _, _ in
                previewZoomScale = 1.0
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
            }
            .focused($focusWorkspace)
    }

    /// Barre horizontale basse : notation / drapeaux / dimensions.
    private var bottomChromeBar: some View {
        HStack(alignment: .center, spacing: 12) {
            if let photo = selectedPhoto {
                starPicker(for: photo)
                flagPicker(for: photo)
                Text("\(photo.pixelWidth)×\(photo.pixelHeight)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 96, alignment: .leading)
                    .lineLimit(1)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private var previewZoomToolbar: some View {
        HStack(spacing: 6) {
            Button {
                previewZoomScale = max(previewZoomMin, previewZoomScale / 1.25)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 15))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(abs(previewZoomScale - previewZoomMin) < 0.000_1)
            .help(String(localized: "preview.zoom.out"))

            Text("\(Int((previewZoomScale * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 40, alignment: .center)

            Button {
                previewZoomScale = min(previewZoomMax, previewZoomScale * 1.25)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 15))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(abs(previewZoomScale - previewZoomMax) < 0.000_1)
            .help(String(localized: "preview.zoom.in"))

            Button {
                previewZoomScale = 1.0
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 15))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(abs(previewZoomScale - 1.0) < 0.000_1)
            .help(String(localized: "preview.zoom.reset"))
        }
        .fixedSize()
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
        case .collection(let sid):
            return photos.filter { $0.collectionID == sid }
        case .monthYear(let year, let month):
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
            if selectedPhotoID == nil {
                selectedPhotoID = filteredPhotos.first?.id
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
    }
}
