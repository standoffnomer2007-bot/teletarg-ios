import Foundation

// MARK: - Transport Domain DTOs

public enum AuthStage: Equatable, Sendable {
    case idle
    case waitTdlibParameters
    case waitPhoneNumber
    case waitCode(phoneNumber: String)
    case waitPassword(hint: String)
    case waitQrConfirmation(link: String)
    case ready(currentUserId: Int64)
    case closed
}

public enum OutgoingChatAction: String, Sendable {
    case typing
    case recordingVoiceNote
    case recordingVideoNote
    case uploadingPhoto
    case uploadingVideo
    case choosingSticker
    case cancel
}

public struct ChatFolderSummary: Hashable, Sendable, Identifiable {
    public let id: Int32
    public var title: String
    public var iconName: String
    public var includedChatIds: Set<Int64>

    public init(id: Int32, title: String, iconName: String, includedChatIds: Set<Int64>) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.includedChatIds = includedChatIds
    }
}

public struct ChatDialogSummary: Hashable, Sendable, Identifiable {
    public let chatId: Int64
    public let peerUserId: Int64?
    public var title: String
    public var kind: ChatKind
    public var lastMessagePreview: String
    public var lastMessageDate: Date
    public var unreadCount: Int
    public var unreadMentionCount: Int
    public var isPinned: Bool
    public var isMuted: Bool
    public var isProtectedContent: Bool
    public var avatarLocalPath: String?
    public var folderIds: Set<Int32>
    public var topicTitles: [Int64: String]

    public var id: Int64 { chatId }

    public init(
        chatId: Int64,
        peerUserId: Int64? = nil,
        title: String,
        kind: ChatKind,
        lastMessagePreview: String,
        lastMessageDate: Date,
        unreadCount: Int = 0,
        unreadMentionCount: Int = 0,
        isPinned: Bool = false,
        isMuted: Bool = false,
        isProtectedContent: Bool = false,
        avatarLocalPath: String? = nil,
        folderIds: Set<Int32> = [],
        topicTitles: [Int64: String] = [:]
    ) {
        self.chatId = chatId
        self.peerUserId = peerUserId
        self.title = title
        self.kind = kind
        self.lastMessagePreview = lastMessagePreview
        self.lastMessageDate = lastMessageDate
        self.unreadCount = unreadCount
        self.unreadMentionCount = unreadMentionCount
        self.isPinned = isPinned
        self.isMuted = isMuted
        self.isProtectedContent = isProtectedContent
        self.avatarLocalPath = avatarLocalPath
        self.folderIds = folderIds
        self.topicTitles = topicTitles
    }
}

public enum TransportEvent: Sendable {
    case authStageChanged(AuthStage)
    case chatsUpdated([ChatDialogSummary])
    case foldersUpdated([ChatFolderSummary])
    case userUpdated(RemoteUserProfile)
    case newMessage(CachedMessageRecord)
    case messageEdited(chatId: Int64, messageId: Int64, newText: String, newCaption: String?, rawJSON: String, editedAt: Date)
    case messagesDeleted(chatId: Int64, messageIds: [Int64])
    case viewOnceFileReady(chatId: Int64, messageId: Int64, senderUserId: Int64, mediaType: MessageContentType, fileURL: URL, mimeType: String, ttlSeconds: Int)
    case activeCallStateChanged(ActiveCallInfo?)
}

public struct ActiveCallInfo: Equatable, Sendable, Identifiable {
    public let id: String
    public let chatId: Int64
    public let title: String
    public var isMuted: Bool
    public var isSpeakerOn: Bool
    public var startedAt: Date

    public init(id: String, chatId: Int64, title: String, isMuted: Bool = false, isSpeakerOn: Bool = false, startedAt: Date = Date()) {
        self.id = id
        self.chatId = chatId
        self.title = title
        self.isMuted = isMuted
        self.isSpeakerOn = isSpeakerOn
        self.startedAt = startedAt
    }
}

// MARK: - Abstract MessengerTransport Protocol

public protocol MessengerTransport: Sendable {
    var events: AsyncStream<TransportEvent> { get }

    // Lifecycle & Auth
    func start(apiId: Int32, apiHash: String) async throws
    func submitPhoneNumber(_ phoneNumber: String) async throws
    func submitAuthCode(_ code: String) async throws
    func submitTwoFactorPassword(_ password: String) async throws
    func requestQrCodeAuthentication() async throws
    func logOut() async throws

    // Chats, Profiles & Messages
    func fetchChats(limit: Int) async throws -> [ChatDialogSummary]
    func fetchUserProfile(userId: Int64) async throws -> RemoteUserProfile
    func fetchMessageHistory(chatId: Int64, fromMessageId: Int64, limit: Int) async throws -> [CachedMessageRecord]
    func sendTextMessage(chatId: Int64, text: String, replyToMessageId: Int64?) async throws -> CachedMessageRecord
    func sendMediaMessage(chatId: Int64, fileURL: URL, caption: String?, isVoice: Bool) async throws
    func forwardMessages(fromChatId: Int64, toChatId: Int64, messageIds: [Int64]) async throws
    func translateText(_ text: String, toLanguageCode: String) async throws -> String

    // Stealth-Interceptable Outgoing Events
    func viewMessages(chatId: Int64, messageIds: [Int64], forceRead: Bool) async throws
    func sendChatAction(chatId: Int64, action: OutgoingChatAction) async throws
    func setOnlineStatus(_ isOnline: Bool) async throws
    func openStory(storySenderChatId: Int64, storyId: Int32) async throws

    // Media Download
    func downloadFile(fileId: Int32) async throws -> URL
}
