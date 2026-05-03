//
//  FilmstripView.swift
//  Zenith
//

import AppKit
import SwiftUI

struct FilmstripView: View {
    let photos: [PhotoRecord]
    @Binding var selection: UUID?

    private let thumbSize: CGFloat = 72

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(photos) { photo in
                    FilmstripCell(
                        photo: photo,
                        isSelected: selection == photo.id,
                        size: thumbSize
                    )
                    .onTapGesture {
                        selection = photo.id
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(height: thumbSize + 36)
        .background(ZenithTheme.glassPanel(RoundedRectangle(cornerRadius: 12)))
    }
}

private struct FilmstripCell: View {
    let photo: PhotoRecord
    let isSelected: Bool
    let size: CGFloat

    @State private var thumb: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumb {
                        Image(nsImage: thumb)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.gray.opacity(0.3)
                    }
                }
                .frame(width: size, height: size)
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
                .frame(width: size)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(photo.filename), \(photo.rating) étoiles")
        .task(id: photo.id) {
            await loadThumb()
        }
    }

    private func loadThumb() async {
        do {
            let url = try photo.resolvedURL()
            let started = url.startAccessingSecurityScopedResource()
            defer { if started { url.stopAccessingSecurityScopedResource() } }
            let img = ThumbnailLoader.thumbnail(for: url, maxPixel: size * 2)
            await MainActor.run { thumb = img }
        } catch {
            thumb = nil
        }
    }
}
