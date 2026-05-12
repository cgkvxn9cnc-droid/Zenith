//
//  CollectionsSidebar.swift
//  Zenith
//

import SwiftUI

private struct FlatCollection: Identifiable {
    let id: UUID
    let name: String
    let depth: Int
    let systemImage: String
}

/// Mode de tri appliqué dans chaque niveau de la hiérarchie : par nom ou par date de création.
/// Persisté via `@AppStorage` pour rester stable d’une session à l’autre.
enum CollectionsSortMode: String, CaseIterable, Identifiable {
    case nameAscending
    case nameDescending
    case dateNewestFirst
    case dateOldestFirst

    var id: String { rawValue }

    var labelKey: String.LocalizationValue {
        switch self {
        case .nameAscending: "sidebar.sort.name_asc"
        case .nameDescending: "sidebar.sort.name_desc"
        case .dateNewestFirst: "sidebar.sort.date_newest"
        case .dateOldestFirst: "sidebar.sort.date_oldest"
        }
    }

    var systemImage: String {
        switch self {
        case .nameAscending: "textformat.abc"
        case .nameDescending: "textformat.abc"
        case .dateNewestFirst: "calendar"
        case .dateOldestFirst: "calendar"
        }
    }
}

struct CollectionsSidebar: View {
    let collections: [CollectionRecord]
    let photos: [PhotoRecord]
    @Binding var selection: SidebarSelection?
    var onAddCollection: () -> Void
    /// Notifie le parent qu’une entrée a été sélectionnée par l’utilisateur (clic explicite).
    /// Utilisé pour basculer vers la Bibliothèque depuis le Catalogue, ou pour ajuster la sélection photo
    /// en restant sur Développement.
    var onSelect: ((SidebarSelection?) -> Void)? = nil

    /// Tri appliqué à chaque niveau de la hiérarchie de dossiers.
    @AppStorage("zenith.collectionsSort") private var sortModeRaw: String = CollectionsSortMode.nameAscending.rawValue

    private var sortMode: CollectionsSortMode {
        CollectionsSortMode(rawValue: sortModeRaw) ?? .nameAscending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selection) {
                /// Entrée "Bibliothèque" : tag explicite `.none` qui signifie « pas de filtre ».
                /// `contentShape` agrandit la zone cliquable à toute la ligne, ce qui rend la sélection plus prévisible.
                sidebarRow(
                    iconName: "books.vertical",
                    label: Text("sidebar.library_all"),
                    isSelected: selection == nil
                ) {
                    selection = nil
                    onSelect?(nil)
                }
                .tag(Optional<SidebarSelection>.none)

                Section {
                    if flattenedCollections.isEmpty {
                        Text("sidebar.collections.empty")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(flattenedCollections) { row in
                            let target = SidebarSelection.collection(row.id)
                            sidebarRow(
                                iconName: row.systemImage,
                                label: Text(row.name),
                                isSelected: selection == target,
                                leadingPadding: CGFloat(row.depth * 14)
                            ) {
                                selection = target
                                onSelect?(target)
                            }
                            .tag(Optional.some(target))
                        }
                    }
                } header: {
                    collectionsHeader
                }

                Section {
                    Button(action: onAddCollection) {
                        Label(String(localized: "sidebar.new_collection"), systemImage: "folder.badge.plus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "sidebar.collections_help"))
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.automatic)
        }
        /// Marges internes : la liste « sidebar » colle sinon aux bords du panneau verre.
        .padding(.horizontal, ZenithTheme.sidebarColumnHorizontalPadding)
        .padding(.top, 4)
        .padding(.bottom, ZenithTheme.sidebarColumnHorizontalPadding)
    }

    /// En-tête de la section Collections : conserve le menu de tri, mais ne se mélange plus avec l'entrée
    /// principale Bibliothèque qui affiche tout le catalogue.
    private var collectionsHeader: some View {
        HStack(spacing: 6) {
            Text("sidebar.section.collections")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)
            Spacer(minLength: 4)
            Menu {
                Picker(selection: Binding(
                    get: { sortMode },
                    set: { sortModeRaw = $0.rawValue }
                )) {
                    ForEach(CollectionsSortMode.allCases) { mode in
                        Label(String(localized: mode.labelKey), systemImage: mode.systemImage)
                            .tag(mode)
                    }
                } label: {
                    Text("sidebar.sort.menu_label")
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22, height: 22)
            .help(String(localized: "sidebar.sort.help"))
            .accessibilityLabel(Text("sidebar.sort.menu_label"))
        }
        .padding(.horizontal, 4)
    }

    private var flattenedCollections: [FlatCollection] {
        let cols = collections
        let collectionsRootID = collectionsRootID

        /// Tri appliqué entre frères : on conserve la hiérarchie globale parent → enfants,
        /// chaque niveau étant trié indépendamment selon le mode choisi par l’utilisateur.
        func sortSiblings(_ siblings: [CollectionRecord]) -> [CollectionRecord] {
            switch sortMode {
            case .nameAscending:
                return siblings.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            case .nameDescending:
                return siblings.sorted { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
            case .dateNewestFirst:
                return siblings.sorted { $0.createdAt > $1.createdAt }
            case .dateOldestFirst:
                return siblings.sorted { $0.createdAt < $1.createdAt }
            }
        }

        func children(of parent: UUID) -> [CollectionRecord] {
            sortSiblings(cols.filter { $0.parentID == parent })
        }

        var rows: [FlatCollection] = []

        func walk(_ node: CollectionRecord, depth: Int) {
            rows.append(
                FlatCollection(id: node.collectionUUID, name: node.name, depth: depth, systemImage: "folder.fill")
            )
            for child in children(of: node.collectionUUID) {
                walk(child, depth: depth + 1)
            }
        }

        let roots: [CollectionRecord]
        if let collectionsRootID {
            /// Logique demandée : la section Collections ne montre que les collections créées par l'utilisateur,
            /// c'est-à-dire les enfants du dossier système "Collections", pas le dossier système lui-même.
            roots = children(of: collectionsRootID)
        } else {
            roots = sortSiblings(cols.filter { $0.parentID == nil && !isSystemCollection($0) })
        }
        for root in roots {
            walk(root, depth: 0)
        }

        return rows
    }

    private var collectionsRootID: UUID? {
        collections.first { $0.name == "Collections" && $0.parentID == nil }?.collectionUUID
    }

    private func isSystemCollection(_ collection: CollectionRecord) -> Bool {
        collection.parentID == nil && (collection.name == "Bibliothèque" || collection.name == "Collections")
    }

    /// Ligne sidebar manuelle : `List(selection:)` propage le clic via le tag, mais on ajoute un `onTapGesture`
    /// qui invoque `onSelect` immédiatement pour pouvoir réagir côté parent (changement de mode, etc.).
    /// `contentShape` garantit que toute la largeur de la ligne est cliquable, et non uniquement le texte/l’icône.
    @ViewBuilder
    private func sidebarRow(
        iconName: String,
        label: Text,
        isSelected: Bool,
        leadingPadding: CGFloat = 0,
        action: @escaping () -> Void
    ) -> some View {
        Label {
            label
                .font(.body)
                .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.92))
                .lineLimit(1)
        } icon: {
            Image(systemName: iconName)
                .foregroundStyle(isSelected ? ZenithTheme.accent : .secondary)
        }
        .padding(.leading, leadingPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}
