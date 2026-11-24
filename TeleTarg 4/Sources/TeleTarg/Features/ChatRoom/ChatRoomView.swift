import SwiftUI

public struct ChatRoomView: View {
    @State var viewModel: ChatRoomViewModel
    let settings: AppSettingsRecord
    let resolveAuthor: (Int64) -> EffectiveUserProfile
    let onOpenProfileEditor: (Int64) -> Void

    public init(
        viewModel: ChatRoomViewModel,
        settings: AppSettingsRecord,
        resolveAuthor: @escaping (Int64) -> EffectiveUserProfile,
        onOpenProfileEditor: @escaping (Int64) -> Void
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.settings = settings
        self.resolveAuthor = resolveAuthor
        self.onOpenProfileEditor = onOpenProfileEditor
    }

    public var body: some View {
        let peerId = viewModel.chat.peerUserId ?? viewModel.chat.chatId
        let headerProfile = resolveAuthor(peerId)
        let discordColors = DiscordColors.palette(
            for: settings.discordPalette,
            customAccentHex: settings.customAccentHex
        )

        VStack(spacing: 0) {
            if let toast = viewModel.toastMessage {
                Text(toast)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.78))
                    .clipShape(Capsule())
                    .padding(.top, 6)
            }

            ProMotionChatTableView(
                messages: viewModel.messages,
                layoutMode: settings.layoutMode,
                settings: settings,
                translatedTexts: viewModel.translatedTexts,
                resolveAuthor: resolveAuthor,
                callbacks: MessageRowActionCallbacks(
                    onCopy: { viewModel.copyMessageText($0) },
                    onReply: { viewModel.replyTarget = $0 },
                    onQuoteSelection: { excerpt, msg in viewModel.quoteSelection(excerpt, from: msg) },
                    onTranslate: { viewModel.translateMessage($0, targetLanguage: settings.translationTargetLanguage) },
                    onShowEditHistory: { viewModel.openEditHistory(for: $0) },
                    onOpenViewOnce: { viewModel.openViewOnceMedia(for: $0) },
                    onShowRawMetadata: { viewModel.selectedRawMetadataMessage = $0 },
                    onOpenAuthorEditor: { onOpenProfileEditor($0) }
                )
            )
            .background(settings.layoutMode == .discord ? discordColors.chatBackground : Color(uiColor: .systemBackground))

            if let reply = viewModel.replyTarget {
                HStack(spacing: 8) {
                    Rectangle().fill(Color.accentColor).frame(width: 3, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.quotedExcerpt == nil ? "Ответ на сообщение" : "Цитирование")
                            .font(.caption.bold())
                        Text(viewModel.quotedExcerpt ?? reply.text)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        viewModel.replyTarget = nil
                        viewModel.quotedExcerpt = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.1))
            }

            composerBar(discordColors: discordColors)
        }
        .navigationTitle(headerProfile.fullName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    onOpenProfileEditor(peerId)
                } label: {
                    VStack(spacing: 1) {
                        Text(headerProfile.fullName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(hex: headerProfile.nameColorHex) ?? .primary)
                        Text(headerProfile.statusDescription)
                            .font(.caption2)
                            .foregroundStyle(headerProfile.isOnline ? .green : .secondary)
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        viewModel.markAllReadManually()
                    } label: {
                        Label("Отметить прочитанным", systemImage: "checkmark.circle")
                    }

                    Button {
                        onOpenProfileEditor(peerId)
                    } label: {
                        Label("Локальный редактор профиля", systemImage: "person.crop.circle.badge.exclamationmark")
                    }

                    Menu("Режим Призрака для чата") {
                        Button("Глобальное правило") { viewModel.updatePerChatStealthRule(nil) }
                        Button("Всегда Призрак (Чёрный список)") { viewModel.updatePerChatStealthRule(.forceGhostOn) }
                        Button("Всегда обычный (Белый список)") { viewModel.updatePerChatStealthRule(.forceGhostOff) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .sheet(item: $viewModel.selectedEditHistoryMessage) { msg in
            EditHistorySheetView(message: msg, revisions: viewModel.editHistoryRevisions)
        }
        .sheet(item: $viewModel.selectedViewOnceRecord) { rec in
            ViewOnceMediaViewer(record: rec)
        }
        .sheet(item: $viewModel.selectedRawMetadataMessage) { msg in
            RawMetadataInspectorView(message: msg)
        }
    }

    private func composerBar(discordColors: DiscordColors) -> some View {
        HStack(spacing: 10) {
            TextField(
                settings.layoutMode == .discord ? "Написать в #\(viewModel.chat.title)..." : "Сообщение...",
                text: $viewModel.composerText,
                axis: .vertical
            )
            .lineLimit(1...5)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(settings.layoutMode == .discord ? discordColors.surfaceElevated : Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .onChange(of: viewModel.composerText) { _, newValue in
                if !newValue.isEmpty {
                    viewModel.notifyTyping()
                }
            }

            Button(action: viewModel.sendCurrentMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(settings.layoutMode == .discord ? discordColors.accent : .blue)
            }
            .disabled(viewModel.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(settings.layoutMode == .discord ? discordColors.sidebarBackground : Color(uiColor: .secondarySystemBackground))
    }
}
