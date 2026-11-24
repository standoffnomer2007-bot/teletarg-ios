import Foundation

/// Координатор входящих событий транспорта:
/// перехватывает новые сообщения, редактирования, удаления и View-Once TTL-медиа,
/// записывая всё в локальную БД GRDB до того, как сервер успеет удалить данные.
public actor AntiDeleteCoordinator {
    private let transport: any MessengerTransport
    private let antiDeleteRepository: any AntiDeleteRepositoryProtocol
    private var listenerTask: Task<Void, Never>?

    public init(
        transport: any MessengerTransport,
        antiDeleteRepository: any AntiDeleteRepositoryProtocol
    ) {
        self.transport = transport
        self.antiDeleteRepository = antiDeleteRepository
    }

    public func startObserving(onEvent: (@Sendable (TransportEvent) async -> Void)? = nil) {
        listenerTask?.cancel()
        listenerTask = Task {
            for await event in transport.events {
                await process(event)
                if let onEvent {
                    await onEvent(event)
                }
            }
        }
    }

    public func stopObserving() {
        listenerTask?.cancel()
        listenerTask = nil
    }

    private func process(_ event: TransportEvent) async {
        switch event {
        case .newMessage(let message):
            try? await antiDeleteRepository.upsertMessage(message)

        case .messageEdited(let chatId, let messageId, let newText, let newCaption, let rawJSON, let editedAt):
            try? await antiDeleteRepository.recordMessageEdit(
                chatId: chatId,
                messageId: messageId,
                newText: newText,
                newCaption: newCaption,
                newRawJSON: rawJSON,
                editedAt: editedAt
            )

        case .messagesDeleted(let chatId, let messageIds):
            try? await antiDeleteRepository.markMessagesDeletedLocally(
                chatId: chatId,
                messageIds: messageIds,
                deletedAt: Date()
            )

        case .viewOnceFileReady(let chatId, let messageId, let senderUserId, let mediaType, let fileURL, let mimeType, let ttlSeconds):
            _ = try? await antiDeleteRepository.cacheViewOnceMedia(
                chatId: chatId,
                messageId: messageId,
                senderUserId: senderUserId,
                mediaType: mediaType,
                decryptedSourceURL: fileURL,
                mimeType: mimeType,
                originalTTLSeconds: ttlSeconds
            )

        default:
            break
        }
    }
}
