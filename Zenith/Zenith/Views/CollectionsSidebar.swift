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

private struct MonthBucket: Identifiable, Hashable {
    let year: Int
    let month: Int
    var id: String { "\(year)-\(month)" }
    let label: String
}

struct CollectionsSidebar: View {
    let collections: [CollectionRecord]
    let photos: [PhotoRecord]
    @Binding var selection: SidebarSelection?
    var onAddCollection: () -> Void

    var body: some View {
        List(selection: $selection) {
            Section {
                Button(action: onAddCollection) {
                    Label(String(localized: "sidebar.new_collection"), systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help(String(localized: "sidebar.collections_help"))

                ForEach(flattenedCollections) { row in
                    Label {
                        Text(row.name)
                    } icon: {
                        Image(systemName: row.systemImage)
                    }
                    .padding(.leading, CGFloat(row.depth * 14))
                    .tag(Optional.some(SidebarSelection.collection(row.id)))
                }
            } header: {
                Text("sidebar.section.hierarchy.library")
            }
            Section("sidebar.section.by_date") {
                ForEach(monthBuckets) { bucket in
                    Text(bucket.label)
                        .tag(Optional.some(SidebarSelection.monthYear(year: bucket.year, month: bucket.month)))
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.automatic)
        .navigationTitle("navigation.title")
    }

    private var monthBuckets: [MonthBucket] {
        var seen = Set<String>()
        var rows: [MonthBucket] = []
        let cal = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        for p in photos {
            let c = cal.dateComponents([.year, .month], from: p.addedAt)
            guard let y = c.year, let m = c.month else { continue }
            let key = "\(y)-\(m)"
            guard seen.insert(key).inserted else { continue }
            var dc = DateComponents()
            dc.year = y
            dc.month = m
            dc.day = 1
            let date = cal.date(from: dc) ?? p.addedAt
            rows.append(MonthBucket(year: y, month: m, label: formatter.string(from: date)))
        }
        return rows.sorted { a, b in
            if a.year != b.year { return a.year > b.year }
            return a.month > b.month
        }
    }

    private var flattenedCollections: [FlatCollection] {
        let cols = collections

        func children(of parent: UUID) -> [CollectionRecord] {
            cols.filter { $0.parentID == parent }.sorted { $0.sortIndex < $1.sortIndex }
        }

        func icon(for name: String) -> String {
            switch name {
            case "Bibliothèque": "books.vertical"
            case "Collections": "folder"
            default: "folder.fill"
            }
        }

        var rows: [FlatCollection] = []

        func walk(_ node: CollectionRecord, depth: Int) {
            rows.append(
                FlatCollection(id: node.collectionUUID, name: node.name, depth: depth, systemImage: icon(for: node.name))
            )
            for child in children(of: node.collectionUUID) {
                walk(child, depth: depth + 1)
            }
        }

        let roots = cols.filter { $0.parentID == nil }.sorted { $0.sortIndex < $1.sortIndex }
        for root in roots {
            walk(root, depth: 0)
        }

        return rows
    }
}
