import SwiftUI

public struct ClassicChatListView: View {
    @Bindable var viewModel: ChatListViewModel
    let showIds: Bool
    let onSelectChat: (ChatDialogSummary) -> Void
    let onOpenProfileEditor: (EffectiveUserProfile, RemoteUserProfile) -> Void
    let onOpenHiddenVault: () -> Void
    let onSwitchToDiscord: () -> Void

    public init(
        viewModel: ChatListViewModel,
        showIds: Bool,
        onSelectChat: @escaping (ChatDialogSummary) -> Void,
        onOpenProfileEditor: @escaping (EffectiveUserProfile, RemoteUserProfile) -> Void,
        onOpenHiddenVault: @escaping () -> Void,
        onSwitchToDiscord: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.showIds = showIds
        self.onSelectChat = onSelectChat
        self.onOpenProfileEditor = onOpenProfileEditor
        self.onOpenHiddenVault = onOpenHiddenVault
        self.onSwitchToDiscord = onSwitchToDiscord
    }

    public var body: some View {
        VStack(spacing: 0) {
            if !viewModel.folders.isEmpty {
                folderStrip
            }

            List {
                ForEach(viewModel.visibleChats) { chat in
                    let effective = viewModel.effectiveProfile(for: chat)
                    Button {
                        onSelectChat(chat)
                    } label: {
                        chatRow(chat: chat, profile: effective)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            let targetId = chat.peerUserId ?? chat.chatId
                            let remote = viewModel.remoteProfiles[targetId] ?? RemoteUserProfile(
                                userId: targetId,
                                firstName: chat.title,
                                avatarLocalPath: chat.avatarLocalPath,
                                isChannelOrGroup: chat.kind != .privateChat
                            )
                            onOpenProfileEditor(effective, remote)
                        } label: {
                            Label("Локальный редактор профиля", systemImage: "person.crop.circle.badge.exclamationmark")
                        }

                        Button {
                            viewModel.setChatHidden(chat.chatId, hidden: true)
                        } label: {
                            Label("Скрыть под Face ID / PIN", systemImage: "lock.shield")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $viewModel.searchText, prompt: "Поиск чатов и ID")
            .refreshable {
                await viewModel.refreshChats()
            }
        }
        .navigationTitle("Чаты")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onOpenHiddenVault) {
                    Image(systemName: "lock.fill")
                }
                .accessibilityLabel("Скрытые чаты")
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: viewModel.toggleMasterGhostMode) {
                    Image(systemName: viewModel.stealthSettings.isMasterGhostEnabled ? "eye.slash.fill" : "eye")
                        .foregroundStyle(viewModel.stealthSettings.isMasterGhostEnabled ? .purple : .primary)
                }
                .accessibilityLabel("Режим Призрак")

                Button(action: onSwitchToDiscord) {
                    Image(systemName: "rectangle.split.3x1")
                }
                .accessibilityLabel("Переключить в Discord-стиль")
            }
        }
    }

    private var folderStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                folderChip(title: "Все", id: nil)
                ForEach(viewModel.folders) { folder in
                    folderChip(title: folder.title, id: folder.id)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func folderChip(title: String, id: Int32?) -> some View {
        let isSelected = viewModel.selectedFolderId == id
        return Button {
            viewModel.selectedFolderId = id
        } label: {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.14))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }

    private func chatRow(chat: ChatDialogSummary, profile: EffectiveUserProfile) -> some View {
        HStack(spacing: 12) {
            AvatarCircleView(
                localPath: profile.avatarLocalPath,
                initials: String(profile.fullName.prefix(1)).uppercased(),
                accentHex: profile.nameColorHex,
                size: 52,
                isOnline: profile.isOnline
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(profile.fullName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color(hex: profile.nameColorHex) ?? .primary)
                        .lineLimit(1)

                    ForEach(profile.badges) { badge in
                        Image(systemName: badge.systemSymbolName)
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }

                    if let emoji = profile.emojiStatus, !emoji.isEmpty {
                        Text(emoji).font(.caption)
                    }

                    Spacer()

                    Text(chat.lastMessageDate, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(chat.lastMessagePreview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    if chat.unreadCount > 0 {
                        Text("\(chat.unreadCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(chat.isMuted ? Color.gray : Color.accentColor)
                            .clipShape(Capsule())
                    }
                }

                if showIds {
                    Text("ID: \(chat.chatId)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
