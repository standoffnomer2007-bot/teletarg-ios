import Foundation

/// Перехватчик исходящих событий Telegram (Режим «Призрак» и «Нечитайка»).
/// Реализует `MessengerTransport` и прозрачно оборачивает любой базовый транспорт (TDLib / WebSocket).
public final class StealthInterceptor: MessengerTransport, Sendable {
    private let underlying: any MessengerTransport
    private let stealthRepository: any StealthSettingsRepositoryProtocol

    public var events: AsyncStream<TransportEvent> {
        underlying.events
    }

    public init(
        underlying: any MessengerTransport,
        stealthRepository: any StealthSettingsRepositoryProtocol
    ) {
        self.underlying = underlying
        self.stealthRepository = stealthRepository
    }

    // MARK: - Auth & Lifecycle (Passthrough)

    public func start(apiId: Int32, apiHash: String) async throws {
        try await underlying.start(apiId: apiId, apiHash: apiHash)
    }

    public func submitPhoneNumber(_ phoneNumber: String) async throws {
        try await underlying.submitPhoneNumber(phoneNumber)
    }

    public func submitAuthCode(_ code: String) async throws {
        try await underlying.submitAuthCode(code)
    }

    public func submitTwoFactorPassword(_ password: String) async throws {
        try await underlying.submitTwoFactorPassword(password)
    }

    public func requestQrCodeAuthentication() async throws {
        try await underlying.requestQrCodeAuthentication()
    }

    public func logOut() async throws {
        try await underlying.logOut()
    }

    // MARK: - Chats & Messages

    public func fetchChats(limit: Int) async throws -> [ChatDialogSummary] {
        try await underlying.fetchChats(limit: limit)
    }

    public func fetchUserProfile(userId: Int64) async throws -> RemoteUserProfile {
        try await underlying.fetchUserProfile(userId: userId)
    }

    public func fetchMessageHistory(chatId: Int64, fromMessageId: Int64, limit: Int) async throws -> [CachedMessageRecord] {
        try await underlying.fetchMessageHistory(chatId: chatId, fromMessageId: fromMessageId, limit: limit)
    }

    public func sendTextMessage(chatId: Int64, text: String, replyToMessageId: Int64?) async throws -> CachedMessageRecord {
        let sent = try await underlying.sendTextMessage(chatId: chatId, text: text, replyToMessageId: replyToMessageId)
        let policy = try await stealthRepository.effectivePolicy(for: chatId)
        if policy.autoOfflineAfterSend {
            try? await underlying.setOnlineStatus(false)
        }
        return sent
    }

    public func sendMediaMessage(chatId: Int64, fileURL: URL, caption: String?, isVoice: Bool) async throws {
        try await underlying.sendMediaMessage(chatId: chatId, fileURL: fileURL, caption: caption, isVoice: isVoice)
        let policy = try await stealthRepository.effectivePolicy(for: chatId)
        if policy.autoOfflineAfterSend {
            try? await underlying.setOnlineStatus(false)
        }
    }

    public func forwardMessages(fromChatId: Int64, toChatId: Int64, messageIds: [Int64]) async throws {
        try await underlying.forwardMessages(fromChatId: fromChatId, toChatId: toChatId, messageIds: messageIds)
        let policy = try await stealthRepository.effectivePolicy(for: toChatId)
        if policy.autoOfflineAfterSend {
            try? await underlying.setOnlineStatus(false)
        }
    }

    public func translateText(_ text: String, toLanguageCode: String) async throws -> String {
        try await underlying.translateText(text, toLanguageCode: toLanguageCode)
    }

    // MARK: - Intercepted Stealth Operations

    /// Блокирует отправку read-receipts (`viewMessages`), если включена «Нечитайка» и не нажата ручная кнопка `forceRead == true`.
    public func viewMessages(chatId: Int64, messageIds: [Int64], forceRead: Bool) async throws {
        if forceRead {
            try await underlying.viewMessages(chatId: chatId, messageIds: messageIds, forceRead: true)
            return
        }
        let policy = try await stealthRepository.effectivePolicy(for: chatId)
        guard !policy.blockReadReceipts else {
            return
        }
        try await underlying.viewMessages(chatId: chatId, messageIds: messageIds, forceRead: false)
    }

    /// Блокирует отправку статусов «печатает...», «записывает голосовое/кружок», «выбирает фото/стикер».
    public func sendChatAction(chatId: Int64, action: OutgoingChatAction) async throws {
        let policy = try await stealthRepository.effectivePolicy(for: chatId)
        guard !policy.blockTypingAndActivities else {
            return
        }
        try await underlying.sendChatAction(chatId: chatId, action: action)
    }

    /// Подавляет отправку статуса `online`, если включён скрытый онлайн.
    public func setOnlineStatus(_ isOnline: Bool) async throws {
        if isOnline {
            let policy = try await stealthRepository.effectivePolicy(for: nil)
            guard !policy.hideOnlinePresence else {
                return
            }
        }
        try await underlying.setOnlineStatus(isOnline)
    }

    /// Подавляет событие просмотра сторис (`openStory`) при активном инкогнито-режиме.
    public func openStory(storySenderChatId: Int64, storyId: Int32) async throws {
        let policy = try await stealthRepository.effectivePolicy(for: storySenderChatId)
        guard !policy.incognitoStories else {
            return
        }
        try await underlying.openStory(storySenderChatId: storySenderChatId, storyId: storyId)
    }

    public func downloadFile(fileId: Int32) async throws -> URL {
        try await underlying.downloadFile(fileId: fileId)
    }
}
