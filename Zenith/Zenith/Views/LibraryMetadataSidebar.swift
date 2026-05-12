//
//  LibraryMetadataSidebar.swift
//  Zenith
//

import SwiftUI

struct LibraryMetadataSidebar: View {
    let photo: PhotoRecord?

    @State private var exifPhotoID: UUID?
    @State private var exifLine: PhotoEXIFFormatter.Line?
    @State private var exifLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("library.metadata.title")
                .font(.headline)
                .padding(.horizontal, ZenithTheme.sidebarColumnHorizontalPadding)
                .padding(.top, ZenithTheme.sidebarColumnSectionVerticalPadding + 2)
                .padding(.bottom, ZenithTheme.sidebarColumnHorizontalPadding)

            Divider()
                .opacity(0.25)

            if let photo {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        metadataRow(label: String(localized: "library.metadata.name"), value: photo.filename)
                        metadataRow(
                            label: String(localized: "library.metadata.dimensions"),
                            value: "\(photo.pixelWidth) × \(photo.pixelHeight)"
                        )
                        metadataRow(label: String(localized: "library.metadata.aspect"), value: aspectLabel(photo))
                        metadataRow(
                            label: String(localized: "library.metadata.added"),
                            value: photo.addedAt.formatted(date: .abbreviated, time: .shortened)
                        )
                        metadataRow(label: String(localized: "library.metadata.rating"), value: "\(photo.rating)/5")
                        metadataRow(label: String(localized: "library.metadata.flag"), value: flagLabel(photo.flag))

                        if exifLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else if let exif = exifLine {
                            Divider()
                                .opacity(0.22)
                            Text("library.metadata.exif.title")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if let iso = exif.iso {
                                metadataRow(label: "ISO", value: iso)
                            }
                            if let focal = exif.focalLengthMM {
                                metadataRow(label: String(localized: "library.metadata.exif.focal"), value: "\(focal) mm")
                            }
                            if let aperture = exif.aperture {
                                metadataRow(label: String(localized: "library.metadata.exif.aperture"), value: "f/\(aperture)")
                            }
                            if let shutter = exif.shutter {
                                metadataRow(label: String(localized: "library.metadata.exif.shutter"), value: shutter)
                            }
                        }
                    }
                    .padding(.horizontal, ZenithTheme.sidebarColumnHorizontalPadding)
                    .padding(.vertical, ZenithTheme.sidebarColumnSectionVerticalPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.automatic)
            } else {
                Spacer(minLength: 0)
                Text("library.metadata.empty")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, ZenithTheme.sidebarColumnHorizontalPadding)
                    .padding(.vertical, ZenithTheme.sidebarColumnSectionVerticalPadding + 6)
                Spacer(minLength: 0)
            }
        }
        .task(id: photo?.id) {
            await refreshExif()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZenithTheme.liquidSidebarGlass(ZenithTheme.sidebarFloatingGlassShape)
        }
        .clipShape(ZenithTheme.sidebarFloatingGlassShape)
    }

    // MARK: - Private

    private func metadataRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func aspectLabel(_ photo: PhotoRecord) -> String {
        guard photo.pixelWidth > 0, photo.pixelHeight > 0 else { return String(localized: "library.metadata.aspect.unknown") }
        if photo.pixelWidth == photo.pixelHeight { return String(localized: "library.metadata.aspect.square") }
        return photo.pixelWidth > photo.pixelHeight
            ? String(localized: "library.metadata.aspect.landscape")
            : String(localized: "library.metadata.aspect.portrait")
    }

    private func flagLabel(_ flag: PhotoPickFlag) -> String {
        switch flag {
        case .none: return String(localized: "library.metadata.flag.none")
        case .pick: return String(localized: "library.metadata.flag.pick")
        case .reject: return String(localized: "library.metadata.flag.reject")
        }
    }

    @MainActor
    private func refreshExif() async {
        guard let photo else {
            exifPhotoID = nil
            exifLine = nil
            exifLoading = false
            return
        }
        if exifPhotoID == photo.id, exifLine != nil { return }
        let photoID = photo.id
        exifPhotoID = photoID
        exifLoading = true
        exifLine = nil
        guard let url = try? photo.resolvedURL() else {
            exifLoading = false
            return
        }

        let result = await Task.detached(priority: .utility) {
            let started = url.startAccessingSecurityScopedResource()
            defer { if started { url.stopAccessingSecurityScopedResource() } }
            return PhotoEXIFFormatter.line(from: url)
        }.value

        guard self.photo?.id == photoID else { return }
        exifLine = result
        exifLoading = false
    }
}
