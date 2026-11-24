import SwiftUI

public struct DiscordShellView: View {
    @Bindable var chatListVM: ChatListViewModel
    let settings: AppSettingsRecord
    let currentUserProfile: EffectiveUserProfile
    let makeChatRoom: (ChatDialogSummary) -> ChatRoomView
    let onOpenSettings: () -> Void
    let onOpenHiddenVault: () -> Void
    let onSwitchToClassic: () -> Void

    @State private var selectedServerFolderId: Int32? = nil
    @State private var isDrawerOpen: Bool = true
    @State private var isMicMuted: Bool = false
    @State private var isDeafened: Bool = false
    @GestureState private var dragTranslation: CGFloat = 0

    public init(
        chatListVM: ChatListViewModel,
        settings: AppSettingsRecord,
        currentUserProfile: EffectiveUserProfile,
        makeChatRoom: @escaping (ChatDialogSummary) -> ChatRoomView,
        onOpenSettings: @escaping () -> Void,
        onOpenHiddenVault: @escaping () -> Void,
        onSwitchToClassic: @escaping () -> Void
    ) {
        self.chatListVM = chatListVM
        self.settings = settings
        self.currentUserProfile = currentUserProfile
        self.makeChatRoom = makeChatRoom
        self.onOpenSettings = onOpenSettings
        self.onOpenHiddenVault = onOpenHiddenVault
        self.onSwitchToClassic = onSwitchToClassic
    }

    public var body: some View {
        let colors = DiscordColors.palette(
            for: settings.discordPalette,
            customAccentHex: settings.customAccentHex
        )

        ZStack(alignment: .bottom) {
            GeometryReader { geo in
                let drawerWidth = min(geo.size.width * 0.84, 340)

                ZStack(alignment: .leading) {
                    // Active Chat Room Layer
                    NavigationStack {
                        if let activeId = chatListVM.selectedChatId,
                           let chat = chatListVM.chats.first(where: { $0.chatId == activeId }) {
                            makeChatRoom(chat)
                                .toolbar {
                                    ToolbarItem(placement: .topBarLeading) {
                                        Button {
                                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                                isDrawerOpen.toggle()
                                            }
                                        } label: {
                                            Image(systemName: "sidebar.left")
                                        }
                                    }
                                }
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "number.circle.fill")
                                    .font(.system(size: 52))
                                    .foregroundStyle(colors.accent)
                                Text("Выберите канал или ЛС")
                                    .font(.headline)
                                    .foregroundStyle(colors.primaryText)
                                Button("Открыть каналы") {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                        isDrawerOpen = true
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(colors.chatBackground)
                        }
                    }

                    if isDrawerOpen {
                        Color.black.opacity(0.45)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                    isDrawerOpen = false
                                }
                            }
                    }

                    // Discord 2-Column Drawer (Server Rail + Channel List + Bottom Status Bar)
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            serverRail(colors: colors)
                                .frame(width: 68)
                                .background(colors.railBackground)

                            channelColumn(colors: colors)
                                .frame(maxWidth: .infinity)
                                .background(colors.sidebarBackground)
                        }

                        userStatusBar(colors: colors)
                    }
                    .frame(width: drawerWidth)
                    .offset(x: (isDrawerOpen ? 0 : -drawerWidth) + dragTranslation)
                    .shadow(color: .black.opacity(0.4), radius: 18, x: 4, y: 0)
                }
                .gesture(
                    DragGesture(minimumDistance: 16)
                        .updating($dragTranslation) { value, state, _ in
                            if isDrawerOpen && value.translation.width < 0 {
                                state = value.translation.width
                            } else if !isDrawerOpen && value.startLocation.x < 44 && value.translation.width > 0 {
                                state = min(value.translation.width, drawerWidth)
                            }
                        }
                        .onEnded { value in
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                if isDrawerOpen && value.translation.width < -60 {
                                    isDrawerOpen = false
                                } else if !isDrawerOpen && value.translation.width > 60 {
                                    isDrawerOpen = true
                                }
                            }
                        }
                )
            }

            if let call = chatListVM.activeCall {
                activeCallOverlay(call: call, colors: colors)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 74)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Left Vertical Server Rail

    private func serverRail(colors: DiscordColors) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                railIconButton(
                    title: "DM",
                    systemIcon: "bubble.left.and.bubble.right.fill",
                    isSelected: selectedServerFolderId == nil,
                    unreadCount: chatListVM.visibleChats.filter { $0.kind == .privateChat }.reduce(0) { $0 + $1.unreadCount },
                    mentionCount: 0,
                    colors: colors
                ) {
                    selectedServerFolderId = nil
                    chatListVM.selectedFolderId = nil
                }

                Divider().background(Color.white.opacity(0.12)).padding(.horizontal, 14)

                ForEach(chatListVM.folders) { folder in
                    let unread = chatListVM.visibleChats
                        .filter { folder.includedChatIds.contains($0.chatId) }
                        .reduce(0) { $0 + $1.unreadCount }
                    let mentions = chatListVM.visibleChats
                        .filter { folder.includedChatIds.contains($0.chatId) }
                        .reduce(0) { $0 + $1.unreadMentionCount }

                    railIconButton(
                        title: String(folder.title.prefix(2)).uppercased(),
                        systemIcon: nil,
                        isSelected: selectedServerFolderId == folder.id,
                        unreadCount: unread,
                        mentionCount: mentions,
                        colors: colors
                    ) {
                        selectedServerFolderId = folder.id
                        chatListVM.selectedFolderId = folder.id
                    }
                }

                Spacer(minLength: 16)

                Button(action: onOpenHiddenVault) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(colors.secondaryText)
                        .frame(width: 44, height: 44)
                        .background(colors.surfaceElevated)
                        .clipShape(Circle())
                }

                Button(action: onSwitchToClassic) {
                    Image(systemName: "iphone")
                        .font(.system(size: 18))
                        .foregroundStyle(colors.secondaryText)
                        .frame(width: 44, height: 44)
                        .background(colors.surfaceElevated)
                        .clipShape(Circle())
                }
            }
            .padding(.vertical, 14)
        }
    }

    private func railIconButton(
        title: String,
        systemIcon: String?,
        isSelected: Bool,
        unreadCount: Int,
        mentionCount: Int,
        colors: DiscordColors,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(isSelected ? Color.white : (unreadCount > 0 ? Color.white.opacity(0.75) : Color.clear))
                .frame(width: 4, height: isSelected ? 32 : (unreadCount > 0 ? 10 : 0))

            Button(action: action) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let systemIcon {
                            Image(systemName: systemIcon).font(.system(size: 20, weight: .semibold))
                        } else {
                            Text(title).font(.system(size: 15, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(isSelected ? colors.accent : colors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: isSelected ? 15 : 23, style: .continuous))

                    if mentionCount > 0 {
                        Text("\(mentionCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .clipShape(Capsule())
                            .offset(x: 4, y: 4)
                    }
                }
            }
        }
    }

    // MARK: - Channel & DM Column

    private func channelColumn(colors: DiscordColors) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(selectedFolderTitle)
                    .font(.headline)
                    .foregroundStyle(colors.primaryText)
                Spacer()
                Button(action: chatListVM.toggleMasterGhostMode) {
                    Image(systemName: chatListVM.stealthSettings.isMasterGhostEnabled ? "eye.slash.fill" : "eye")
                        .foregroundStyle(chatListVM.stealthSettings.isMasterGhostEnabled ? colors.accent : colors.secondaryText)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)

            Divider().background(Color.white.opacity(0.08))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    let channels = chatListVM.visibleChats.filter { $0.kind == .channel || $0.kind == .supergroup || $0.kind == .forum }
                    let dms = chatListVM.visibleChats.filter { $0.kind == .privateChat || $0.kind == .secretChat || $0.kind == .basicGroup }

                    if !channels.isEmpty {
                        sectionHeader("ТЕКСТОВЫЕ КАНАЛЫ", colors: colors)
                        ForEach(channels) { chat in
                            channelRow(chat: chat, prefix: "#", colors: colors)
                        }
                    }

                    if !dms.isEmpty {
                        sectionHeader("ЛИЧНЫЕ СООБЩЕНИЯ", colors: colors)
                        ForEach(dms) { chat in
                            channelRow(chat: chat, prefix: "@", colors: colors)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
            }
        }
    }

    private var selectedFolderTitle: String {
        if let id = selectedServerFolderId, let folder = chatListVM.folders.first(where: { $0.id == id }) {
            return folder.title
        }
        return "TeleTarg — Личные"
    }

    private func sectionHeader(_ title: String, colors: DiscordColors) -> some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(colors.secondaryText)
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func channelRow(chat: ChatDialogSummary, prefix: String, colors: DiscordColors) -> some View {
        let profile = chatListVM.effectiveProfile(for: chat)
        let isSelected = chatListVM.selectedChatId == chat.chatId
        return Button {
            chatListVM.selectedChatId = chat.chatId
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                isDrawerOpen = false
            }
        } label: {
            HStack(spacing: 8) {
                Text(prefix)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(colors.secondaryText)
                Text(profile.fullName)
                    .font(.subheadline.weight(chat.unreadCount > 0 ? .bold : .medium))
                    .foregroundStyle(isSelected || chat.unreadCount > 0 ? colors.primaryText : colors.secondaryText)
                    .lineLimit(1)
                Spacer()
                if chat.unreadCount > 0 {
                    Text("\(chat.unreadCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(colors.accent)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? colors.surfaceElevated : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom User Status Bar & Active Call Overlay

    private func userStatusBar(colors: DiscordColors) -> some View {
        HStack(spacing: 10) {
            AvatarCircleView(
                localPath: currentUserProfile.avatarLocalPath,
                initials: String(currentUserProfile.fullName.prefix(1)).uppercased(),
                accentHex: currentUserProfile.nameColorHex,
                size: 34,
                isOnline: !chatListVM.stealthSettings.isMasterGhostEnabled
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(currentUserProfile.fullName)
                    .font(.caption.bold())
                    .foregroundStyle(colors.primaryText)
                    .lineLimit(1)
                Text(chatListVM.stealthSettings.isMasterGhostEnabled ? "Призрак активен" : currentUserProfile.statusDescription)
                    .font(.caption2)
                    .foregroundStyle(chatListVM.stealthSettings.isMasterGhostEnabled ? colors.accent : colors.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            Button { isMicMuted.toggle() } label: {
                Image(systemName: isMicMuted ? "mic.slash.fill" : "mic.fill")
                    .foregroundStyle(isMicMuted ? .red : colors.secondaryText)
            }

            Button { isDeafened.toggle() } label: {
                Image(systemName: isDeafened ? "speaker.slash.fill" : "headphones")
                    .foregroundStyle(isDeafened ? .red : colors.secondaryText)
            }

            Button(action: chatListVM.toggleMasterGhostMode) {
                Image(systemName: chatListVM.stealthSettings.isMasterGhostEnabled ? "eye.slash.fill" : "eye")
                    .foregroundStyle(chatListVM.stealthSettings.isMasterGhostEnabled ? colors.accent : colors.secondaryText)
            }

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(colors.secondaryText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(colors.railBackground)
    }

    private func activeCallOverlay(call: ActiveCallInfo, colors: DiscordColors) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Голосовой канал: \(call.title)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                Text("Подключено")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
            Spacer()
            Button {
                chatListVM.activeCall = nil
            } label: {
                Image(systemName: "phone.down.fill")
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Color.red)
                    .clipShape(Circle())
            }
        }
        .padding(12)
        .background(colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 10)
    }
}
