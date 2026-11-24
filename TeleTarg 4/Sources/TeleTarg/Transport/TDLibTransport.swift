import Foundation
import TDLibKit

public enum TDLibTransportError: Error, LocalizedError, Sendable {
    case notStarted
    case invalidFileDownload
    case userNotFound(Int64)

    public var errorDescription: String? {
        switch self {
        case .notStarted: return "TDLib клиент ещё не инициализирован."
        case .invalidFileDownload: return "Не удалось загрузить файл из Telegram."
        case .userNotFound(let id): return "Пользователь \(id) не найден."
        }
    }
}

public actor TDLibTransport: MessengerTransport {
    private let manager = TDLibClientManager()
    private var client: TDLibClient?
    private var currentApiId: Int32 = 0
    private var currentApiHash: String = ""
    private var cachedChats: [Int64: ChatDialogSummary] = [:]
    private var cachedUsers: [Int64: RemoteUserProfile] = [:]

    private let eventContinuation: AsyncStream<TransportEvent>.Continuation
    public nonisolated let events: AsyncStream<TransportEvent>

    public init() {
        var continuation: AsyncStream<TransportEvent>.Continuation?
        self.events = AsyncStream { cont in
            continuation = cont
        }
        self.eventContinuation = continuation!
    }

    public func start(apiId: Int32, apiHash: String) async throws {
        self.currentApiId = apiId
        self.currentApiHash = apiHash

        let tdClient = manager.createClient { [weak self] data, tdlibClient in
            guard let self else { return }
            do {
                let update = try tdlibClient.decoder.decode(Update.self, from: data)
                Task {
                    await self.handleUpdate(update, rawData: data)
                }
            } catch {
                // Ignore unrecognized low-level TDLib updates safely
            }
        }
        self.client = tdClient
        try? await tdClient.setLogVerbosityLevel(newVerbosityLevel: 1)
    }

    public func submitPhoneNumber(_ phoneNumber: String) async throws {
        let tdClient = try requireClient()
        _ = try await tdClient.setAuthenticationPhoneNumber(
            phoneNumber: phoneNumber,
            settings: nil
        )
    }

    public func submitAuthCode(_ code: String) async throws {
        let tdClient = try requireClient()
        _ = try await tdClient.checkAuthenticationCode(code: code)
    }

    public func submitTwoFactorPassword(_ password: String) async throws {
        let tdClient = try requireClient()
        _ = try await tdClient.checkAuthenticationPassword(password: password)
    }

    public func requestQrCodeAuthentication() async throws {
        let tdClient = try requireClient()
        _ = try await tdClient.requestQrCodeAuthentication(otherUserIds: [])
    }

    public func logOut() async throws {
        let tdClient = try requireClient()
        _ = try await tdClient.logOut()
    }

    public func fetchChats(limit: Int = 100) async throws -> [ChatDialogSummary] {
        let tdClient = try requireClient()
        let chats = try await tdClient.getChats(chatList: .chatListMain, limit: limit)
        var results: [ChatDialogSummary] = []
        results.reserveCapacity(chats.chatIds.count)

        for chatId in chats.chatIds {
            if let chat = try? await tdClient.getChat(chatId: chatId) {
                let summary = mapChat(chat)
                cachedChats[chatId] = summary
                results.append(summary)
            }
        }
        eventContinuation.yield(.chatsUpdated(results))
        return results
    }

    public func fetchUserProfile(userId: Int64) async throws -> RemoteUserProfile {
        let tdClient = try requireClient()
        let user = try await tdClient.getUser(userId: userId)
        let fullInfo = try? await tdClient.getUserFullInfo(userId: userId)
        let profile = mapUser(user, fullInfo: fullInfo)
        cachedUsers[userId] = profile
        return profile
    }

    public func fetchMessageHistory(chatId: Int64, fromMessageId: Int64 = 0, limit: Int = 50) async throws -> [CachedMessageRecord] {
        let tdClient = try requireClient()
        let response = try await tdClient.getChatHistory(
            chatId: chatId,
            fromMessageId: fromMessageId,
            limit: limit,
            offset: 0,
            onlyLocal: false
        )
        let messages = response.messages ?? []
        return messages.map { mapMessage($0) }.reversed()
    }

    public func sendTextMessage(chatId: Int64, text: String, replyToMessageId: Int64?) async throws -> CachedMessageRecord {
        let tdClient = try requireClient()
        let replyTo: InputMessageReplyTo? = replyToMessageId.map {
            .inputMessageReplyToMessage(.init(messageId: $0, quote: nil))
        }
        let content = InputMessageContent.inputMessageText(
            .init(clearDraft: true, linkPreviewOptions: nil, text: FormattedText(entities: [], text: text))
        )
        let sent = try await tdClient.sendMessage(
            chatId: chatId,
            inputMessageContent: content,
            messageThreadId: 0,
            options: nil,
            replyMarkup: nil,
            replyTo: replyTo
        )
        return mapMessage(sent)
    }

    public func sendMediaMessage(chatId: Int64, fileURL: URL, caption: String?, isVoice: Bool) async throws {
        let tdClient = try requireClient()
        let inputFile = InputFile.inputFileLocal(.init(path: fileURL.path))
        let formattedCaption = caption.map { FormattedText(entities: [], text: $0) }
        let content: InputMessageContent
        if isVoice {
            content = .inputMessageVoiceNote(
                .init(
                    caption: formattedCaption,
                    duration: 0,
                    selfDestructType: nil,
                    voiceNote: inputFile,
                    waveform: Data()
                )
            )
        } else {
            content = .inputMessageDocument(
                .init(
                    caption: formattedCaption,
                    disableContentTypeDetection: false,
                    document: inputFile,
                    thumbnail: nil
                )
            )
        }
        _ = try await tdClient.sendMessage(
            chatId: chatId,
            inputMessageContent: content,
            messageThreadId: 0,
            options: nil,
            replyMarkup: nil,
            replyTo: nil
        )
    }

    public func forwardMessages(fromChatId: Int64, toChatId: Int64, messageIds: [Int64]) async throws {
        let tdClient = try requireClient()
        _ = try await tdClient.forwardMessages(
            chatId: toChatId,
            fromChatId: fromChatId,
            messageIds: messageIds,
            messageThreadId: 0,
            options: nil,
            removeCaption: false,
            sendCopy: false
        )
    }

    public func translateText(_ text: String, toLanguageCode: String) async throws -> String {
        let tdClient = try requireClient()
        let translated = try await tdClient.translateText(
            text: FormattedText(entities: [], text: text),
            toLanguageCode: toLanguageCode
        )
        return translated.text
    }

    public func viewMessages(chatId: Int64, messageIds: [Int64], forceRead: Bool) async throws {
        let tdClient = try requireClient()
        _ = try await tdClient.viewMessages(
            chatId: chatId,
            forceRead: forceRead,
            messageIds: messageIds,
            source: nil
        )
    }

    public func sendChatAction(chatId: Int64, action: OutgoingChatAction) async throws {
        let tdClient = try requireClient()
        let tdAction: ChatAction
        switch action {
        case .typing: tdAction = .chatActionTyping
        case .recordingVoiceNote: tdAction = .chatActionRecordingVoiceNote
        case .recordingVideoNote: tdAction = .chatActionRecordingVideoNote
        case .uploadingPhoto: tdAction = .chatActionUploadingPhoto(.init(progress: 0))
        case .uploadingVideo: tdAction = .chatActionUploadingVideo(.init(progress: 0))
        case .choosingSticker: tdAction = .chatActionChoosingSticker
        case .cancel: tdAction = .chatActionCancel
        }
        _ = try await tdClient.sendChatAction(action: tdAction, businessConnectionId: "", chatId: chatId, messageThreadId: 0)
    }

    public func setOnlineStatus(_ isOnline: Bool) async throws {
        let tdClient = try requireClient()
        _ = try await tdClient.setOption(
            name: "online",
            value: .optionValueBoolean(.init(value: isOnline))
        )
    }

    public func openStory(storySenderChatId: Int64, storyId: Int32) async throws {
        let tdClient = try requireClient()
        _ = try await tdClient.openStory(storyId: storyId, storySenderChatId: storySenderChatId)
    }

    public func downloadFile(fileId: Int32) async throws -> URL {
        let tdClient = try requireClient()
        let file = try await tdClient.downloadFile(
            fileId: fileId,
            limit: 0,
            offset: 0,
            priority: 32,
            synchronous: true
        )
        guard !file.local.path.isEmpty else {
            throw TDLibTransportError.invalidFileDownload
        }
        return URL(fileURLWithPath: file.local.path)
    }

    // MARK: - Incoming TDLib Updates

    private func handleUpdate(_ update: Update, rawData: Data) async {
        let rawJSON = String(data: rawData, encoding: .utf8) ?? "{}"

        switch update {
        case .updateAuthorizationState(let stateUpdate):
            await handleAuthState(stateUpdate.authorizationState)

        case .updateNewMessage(let msgUpdate):
            let record = mapMessage(msgUpdate.message, rawJSON: rawJSON)
            eventContinuation.yield(.newMessage(record))
            await inspectAndCacheViewOnceIfNeeded(msgUpdate.message)

        case .updateMessageContent(let editUpdate):
            let (text, caption) = extractTextAndCaption(from: editUpdate.newContent)
            eventContinuation.yield(
                .messageEdited(
                    chatId: editUpdate.chatId,
                    messageId: editUpdate.messageId,
                    newText: text,
                    newCaption: caption,
                    rawJSON: rawJSON,
                    editedAt: Date()
                )
            )

        case .updateDeleteMessages(let deleteUpdate):
            if !deleteUpdate.fromCache {
                eventContinuation.yield(
                    .messagesDeleted(chatId: deleteUpdate.chatId, messageIds: deleteUpdate.messageIds)
                )
            }

        case .updateUser(let userUpdate):
            let profile = mapUser(userUpdate.user, fullInfo: nil)
            cachedUsers[profile.userId] = profile
            eventContinuation.yield(.userUpdated(profile))

        case .updateChatFolders(let foldersUpdate):
            let mapped = foldersUpdate.chatFolders.map { folder in
                ChatFolderSummary(
                    id: Int32(folder.id),
                    title: folder.name.text.text,
                    iconName: folder.icon.name,
                    includedChatIds: []
                )
            }
            eventContinuation.yield(.foldersUpdated(mapped))

        default:
            break
        }
    }

    private func handleAuthState(_ state: AuthorizationState) async {
        switch state {
        case .authorizationStateWaitTdlibParameters:
            eventContinuation.yield(.authStageChanged(.waitTdlibParameters))
            await configureTdlibParameters()
        case .authorizationStateWaitPhoneNumber:
            eventContinuation.yield(.authStageChanged(.waitPhoneNumber))
        case .authorizationStateWaitCode(let info):
            eventContinuation.yield(.authStageChanged(.waitCode(phoneNumber: info.codeInfo.phoneNumber)))
        case .authorizationStateWaitPassword(let info):
            eventContinuation.yield(.authStageChanged(.waitPassword(hint: info.passwordHint)))
        case .authorizationStateWaitOtherDeviceConfirmation(let info):
            eventContinuation.yield(.authStageChanged(.waitQrConfirmation(link: info.link)))
        case .authorizationStateReady:
            if let me = try? await client?.getMe() {
                eventContinuation.yield(.authStageChanged(.ready(currentUserId: me.id)))
            } else {
                eventContinuation.yield(.authStageChanged(.ready(currentUserId: 0)))
            }
        case .authorizationStateClosed:
            eventContinuation.yield(.authStageChanged(.closed))
        default:
            break
        }
    }

    private func configureTdlibParameters() async {
        guard let tdClient = client else { return }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let tdDir = appSupport.appendingPathComponent("TeleTarg/TDLib", isDirectory: true)
        try? FileManager.default.createDirectory(at: tdDir, withIntermediateDirectories: true)

        _ = try? await tdClient.setTdlibParameters(
            apiHash: currentApiHash,
            apiId: Int(currentApiId),
            applicationVersion: "1.0.0",
            databaseDirectory: tdDir.appendingPathComponent("db").path,
            databaseEncryptionKey: Data(),
            deviceModel: "iPhone",
            filesDirectory: tdDir.appendingPathComponent("files").path,
            systemLanguageCode: "ru",
            systemVersion: "iOS 17",
            useChatInfoDatabase: true,
            useFileDatabase: true,
            useMessageDatabase: true,
            useSecretChats: true,
            useTestDc: false
        )
    }

    private func inspectAndCacheViewOnceIfNeeded(_ message: Message) async {
        guard let ttlType = message.selfDestructType else { return }
        let ttlSeconds: Int
        switch ttlType {
        case .messageSelfDestructTypeTimer(let timer):
            ttlSeconds = timer.selfDestructTime
        case .messageSelfDestructTypeImmediately:
            ttlSeconds = 1
        }

        let senderId: Int64
        switch message.senderId {
        case .messageSenderUser(let u): senderId = u.userId
        case .messageSenderChat(let c): senderId = c.chatId
        }

        var targetFileId: Int32?
        var mediaType: MessageContentType = .photo
        var mimeType = "application/octet-stream"

        switch message.content {
        case .messagePhoto(let photo):
            targetFileId = photo.photo.sizes.last?.photo.id.flatMap { Int32($0) }
            mediaType = .photo
            mimeType = "image/jpeg"
        case .messageVideo(let video):
            targetFileId = Int32(video.video.video.id)
            mediaType = .video
            mimeType = video.video.mimeType
        case .messageVoiceNote(let voice):
            targetFileId = Int32(voice.voiceNote.voice.id)
            mediaType = .voiceNote
            mimeType = voice.voiceNote.mimeType
        case .messageVideoNote(let videoNote):
            targetFileId = Int32(videoNote.videoNote.video.id)
            mediaType = .videoNote
            mimeType = "video/mp4"
        default:
            break
        }

        guard let fileId = targetFileId, let fileURL = try? await downloadFile(fileId: fileId) else { return }
        eventContinuation.yield(
            .viewOnceFileReady(
                chatId: message.chatId,
                messageId: message.id,
                senderUserId: senderId,
                mediaType: mediaType,
                fileURL: fileURL,
                mimeType: mimeType,
                ttlSeconds: ttlSeconds
            )
        )
    }

    // MARK: - Mappers

    private func requireClient() throws -> TDLibClient {
        guard let client else { throw TDLibTransportError.notStarted }
        return client
    }

    private func mapChat(_ chat: Chat) -> ChatDialogSummary {
        let kind: ChatKind
        var peerUserId: Int64?
        switch chat.type {
        case .chatTypePrivate(let p):
            kind = .privateChat
            peerUserId = p.userId
        case .chatTypeBasicGroup:
            kind = .basicGroup
        case .chatTypeSupergroup(let s):
            kind = s.isChannel ? .channel : .supergroup
        case .chatTypeSecret(let sec):
            kind = .secretChat
            peerUserId = sec.userId
        }

        let preview: String
        let lastDate: Date
        if let last = chat.lastMessage {
            let (text, caption) = extractTextAndCaption(from: last.content)
            preview = text.isEmpty ? (caption ?? "Медиафайл") : text
            lastDate = Date(timeIntervalSince1970: TimeInterval(last.date))
        } else {
            preview = ""
            lastDate = Date()
        }

        return ChatDialogSummary(
            chatId: chat.id,
            peerUserId: peerUserId,
            title: chat.title,
            kind: kind,
            lastMessagePreview: preview,
            lastMessageDate: lastDate,
            unreadCount: chat.unreadCount,
            unreadMentionCount: chat.unreadMentionCount,
            isPinned: chat.positions.contains(where: { $0.isPinned }),
            isMuted: chat.notificationSettings.muteFor > 0,
            isProtectedContent: chat.hasProtectedContent,
            avatarLocalPath: chat.photo?.small.local.path
        )
    }

    private func mapUser(_ user: User, fullInfo: UserFullInfo?) -> RemoteUserProfile {
        var badges: [ProfileBadge] = []
        if user.isVerified { badges.append(.verified) }
        if user.isPremium { badges.append(.premium) }
        if user.isScam { badges.append(.scam) }
        if user.isFake { badges.append(.fake) }

        let isOnline: Bool
        let statusText: String
        switch user.status {
        case .userStatusOnline:
            isOnline = true
            statusText = "в сети"
        case .userStatusOffline(let off):
            isOnline = false
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            statusText = "был(а) в \(formatter.string(from: Date(timeIntervalSince1970: TimeInterval(off.wasOnline))))"
        case .userStatusRecently:
            isOnline = false
            statusText = "был(а) недавно"
        case .userStatusLastWeek:
            isOnline = false
            statusText = "был(а) на этой неделе"
        case .userStatusLastMonth:
            isOnline = false
            statusText = "был(а) в этом месяце"
        case .userStatusEmpty:
            isOnline = false
            statusText = "давно"
        }

        return RemoteUserProfile(
            userId: user.id,
            firstName: user.firstName,
            lastName: user.lastName,
            username: user.usernames?.activeUsernames.first,
            phoneNumber: user.phoneNumber.isEmpty ? nil : user.phoneNumber,
            avatarLocalPath: user.profilePhoto?.small.local.path,
            avatarIsVideo: false,
            bio: fullInfo?.bio?.text,
            isOnline: isOnline,
            statusDescription: statusText,
            badges: badges
        )
    }

    private func mapMessage(_ msg: Message, rawJSON: String = "{}") -> CachedMessageRecord {
        let senderId: Int64
        switch msg.senderId {
        case .messageSenderUser(let u): senderId = u.userId
        case .messageSenderChat(let c): senderId = c.chatId
        }

        let (text, caption) = extractTextAndCaption(from: msg.content)
        let contentType = extractContentType(from: msg.content)
        let isViewOnce = msg.selfDestructType != nil
        var ttl: Int?
        if case .messageSelfDestructTypeTimer(let t) = msg.selfDestructType {
            ttl = t.selfDestructTime
        } else if case .messageSelfDestructTypeImmediately = msg.selfDestructType {
            ttl = 1
        }

        return CachedMessageRecord(
            chatId: msg.chatId,
            messageId: msg.id,
            senderUserId: senderId,
            replyToMessageId: nil,
            threadTopicId: msg.messageThreadId == 0 ? nil : msg.messageThreadId,
            contentType: contentType,
            text: text,
            caption: caption,
            localMediaPath: nil,
            isOutgoing: msg.isOutgoing,
            isReadByPeer: false,
            isProtectedContent: !msg.canBeForwarded,
            isViewOnce: isViewOnce,
            selfDestructSeconds: ttl,
            sentAt: Date(timeIntervalSince1970: TimeInterval(msg.date)),
            editedAt: msg.editDate > 0 ? Date(timeIntervalSince1970: TimeInterval(msg.editDate)) : nil,
            editCount: msg.editDate > 0 ? 1 : 0,
            isDeletedLocally: false,
            deletedAt: nil,
            rawJSON: rawJSON
        )
    }

    private func extractContentType(from content: MessageContent) -> MessageContentType {
        switch content {
        case .messageText: return .text
        case .messagePhoto: return .photo
        case .messageVideo: return .video
        case .messageVideoNote: return .videoNote
        case .messageVoiceNote: return .voiceNote
        case .messageDocument: return .document
        case .messageAudio: return .audio
        case .messageSticker: return .sticker
        case .messageAnimation: return .animation
        case .messagePoll: return .poll
        case .messageCall: return .call
        default: return .unsupported
        }
    }

    private func extractTextAndCaption(from content: MessageContent) -> (String, String?) {
        switch content {
        case .messageText(let t): return (t.text.text, nil)
        case .messagePhoto(let p): return ("", p.caption.text.isEmpty ? nil : p.caption.text)
        case .messageVideo(let v): return ("", v.caption.text.isEmpty ? nil : v.caption.text)
        case .messageDocument(let d): return (d.document.fileName, d.caption.text.isEmpty ? nil : d.caption.text)
        case .messageVoiceNote(let vn): return ("Голосовое сообщение", vn.caption.text.isEmpty ? nil : vn.caption.text)
        case .messageVideoNote: return ("Видеосообщение", nil)
        case .messageSticker(let s): return ("Стикер \(s.sticker.emoji)", nil)
        case .messagePoll(let p): return ("Опрос: \(p.poll.question.text)", nil)
        case .messageCall: return ("Звонок", nil)
        default: return ("Вложение", nil)
        }
    }
}
