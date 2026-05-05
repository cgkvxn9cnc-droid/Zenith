//
//  LibraryGridView.swift
//  Zenith
//

import SwiftData
import SwiftUI

struct LibraryGridView: View {
    @Environment(\.modelContext) private var modelContext
    let photos: [PhotoRecord]
    @Binding var selectedPhotoID: UUID?

    private let columns = [GridItem(.adaptive(minimum: 148), spacing: 14, alignment: .top)]

    var body: some View {
        Group {
            if photos.isEmpty {
                ContentUnavailableView {
                    Label("library.grid.empty.title", systemImage: "photo.on.rectangle.angled")
                } description: {
                    Text("library.grid.empty.subtitle")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(photos) { photo in
                            LibraryGridCell(
                                photo: photo,
                                isSelected: selectedPhotoID == photo.id,
                                onSelect: { selectedPhotoID = photo.id },
                                onSetRating: { rating in
                                    photo.rating = rating
                                    try? modelContext.save()
                                }
                            )
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ZenithTheme.pageBackground)
    }
}

private struct LibraryGridCell: View {
    let photo: PhotoRecord
    let isSelected: Bool
    let onSelect: () -> Void
    let onSetRating: (Int) -> Void

    @State private var thumb: NSImage?
    private let thumbSize: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumb {
                        Image(nsImage: thumb)
                            .resizable()
                            .scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    }
                }
                .frame(width: thumbSize, height: thumbSize)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? ZenithTheme.accent : Color.primary.opacity(0.12), lineWidth: isSelected ? 2.5 : 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onTapGesture { onSelect() }

                if photo.rating > 0 {
                    Text(String(repeating: "★", count: photo.rating))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(6)
                }
            }

            Text(photo.filename)
                .font(.caption)
                .lineLimit(2)
                .frame(width: thumbSize, alignment: .leading)
                .foregroundStyle(.primary)

            HStack(spacing: 2) {
                ForEach(1 ... 5, id: \.self) { n in
                    Button {
                        if n == photo.rating {
                            onSetRating(0)
                        } else {
                            onSetRating(n)
                        }
                    } label: {
                        Image(systemName: n <= photo.rating ? "star.fill" : "star")
                            .font(.system(size: 11))
                            .foregroundStyle(n <= photo.rating ? Color.yellow : Color.secondary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task(id: photo.id) {
            await loadThumb()
        }
    }

    private func loadThumb() async {
        do {
            let url = try photo.resolvedURL()
            let started = url.startAccessingSecurityScopedResource()
            defer { if started { url.stopAccessingSecurityScopedResource() } }
            let img = ThumbnailLoader.thumbnail(for: url, maxPixel: thumbSize * 2)
            await MainActor.run { thumb = img }
        } catch {
            await MainActor.run { thumb = nil }
        }
    }
}
