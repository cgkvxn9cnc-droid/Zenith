//
//  CatalogOverviewView.swift
//  Zenith
//

import SwiftUI

struct CatalogOverviewView: View {
    let photoCount: Int
    let collectionFolderCount: Int
    let onImportPhotos: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("catalog.overview.title")
                    .font(.largeTitle.weight(.bold))

                Text("catalog.overview.body")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 24) {
                    statBlock(value: "\(photoCount)", labelKey: "catalog.overview.stat_photos")
                    statBlock(value: "\(collectionFolderCount)", labelKey: "catalog.overview.stat_collections")
                }
                .padding(.vertical, 8)

                Button {
                    onImportPhotos()
                } label: {
                    Label("catalog.overview.import", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(ZenithTheme.pageBackground)
    }

    private func statBlock(value: String, labelKey: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title.weight(.semibold))
                .monospacedDigit()
            Text(labelKey)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}
