//
//  ChatPanel.swift
//  Zenith
//

import SwiftData
import SwiftUI

struct ChatPanel: View {
    let photos: [PhotoRecord]
    let selectedPhotoID: UUID?

    @Query(sort: \ChatMessageRecord.sentAt, order: .forward) private var messages: [ChatMessageRecord]
    @Query(sort: \PresetRecord.createdAt, order: .reverse) private var presets: [PresetRecord]

    @Environment(\.modelContext) private var modelContext
    @AppStorage("zenith.collaborationRole") private var collaborationRoleRaw = "edit"

    private var canModerateChat: Bool {
        collaborationRoleRaw == "edit"
    }

    @State private var draft = ""
    @State private var mentionPhotoID: UUID?
    @State private var attachPresetID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("chat.header")
                .font(.headline)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(messages, id: \.id) { msg in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(msg.author)
                                        .font(.caption.bold())
                                    Spacer()
                                    Text(msg.sentAt.formatted(date: .omitted, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    if canModerateChat {
                                        Button(role: .destructive) {
                                            modelContext.delete(msg)
                                            try? modelContext.save()
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.borderless)
                                        .help(String(localized: "chat.delete"))
                                    }
                                }
                                Text(msg.body)
                                    .font(.subheadline)
                                if msg.mentionedPhotoID != nil {
                                    Text("chat.mention.hint")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                if msg.sharedPresetID != nil {
                                    Text("chat.preset_attached")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(ZenithTheme.glassPanel(RoundedRectangle(cornerRadius: 8)))
                            .id(msg.id)
                        }
                    }
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            .frame(minHeight: 160)

            HStack {
                Menu {
                    Button(String(localized: "chat.mention")) {
                        mentionPhotoID = selectedPhotoID
                    }
                    .disabled(selectedPhotoID == nil)

                    Menu(String(localized: "chat.share_preset")) {
                        ForEach(presets) { preset in
                            Button(preset.name) {
                                attachPresetID = preset.id
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }

                TextField("chat.message.placeholder", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1 ... 4)

                Button {
                    send()
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }
            .disabled(collaborationRoleRaw != "edit")
            .help(collaborationRoleRaw != "edit" ? String(localized: "chat.readonly.composer") : "")
        }
        .padding(16)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let msg = ChatMessageRecord(
            author: String(localized: "chat.author.self"),
            body: text,
            mentionedPhotoID: mentionPhotoID,
            sharedPresetID: attachPresetID
        )
        modelContext.insert(msg)
        draft = ""
        mentionPhotoID = nil
        attachPresetID = nil
        try? modelContext.save()
    }
}
