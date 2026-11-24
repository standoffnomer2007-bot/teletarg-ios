import Foundation
import Observation
import UIKit

@MainActor
@Observable
public final class ChatRoomViewModel {
    public let chat: ChatDialogSummary
    public var messages: [CachedMessageRecord] = []
    public var composerText: String = ""
    public var replyTarget: CachedMessageRecord? = nil
    public var quotedExcerpt: String? = nil
    public var translatedTexts: [Int64: String] = [:]
    public var selectedEditHistoryMessage: CachedMessageRecord? = nil
    public var editHistoryRevisions: [MessageEditRevisionRecord] = []
    public var selectedViewOnceRecord: ViewOnceMediaCacheRecord? = nil
    public var selectedRawMetadataMessage: CachedMessageRecord? = nil
    public var chatStealthRule: StealthChatRuleRecord? = nil
    public var toastMessage: String? = nil

    private let transport: any MessengerTransport
    private let antiDeleteRepository: any AntiDeleteRepositoryProtocol
    private let stealthRepository: any StealthSettingsRepositoryProtocol
    private var observationTask: Task<Void, Never>?

    public init(
        chat: ChatDialogSummary,
        transport: any MessengerTransport,
        antiDeleteRepository: any AntiDeleteRepositoryProtocol,
        stealthRepository: any StealthSettingsRepositoryProtocol
    ) {
        self.chat = chat
        self.transport = transport
        self.antiDeleteRepository = antiDeleteRepository
        self.stealthRepository = stealthRepository
    }

    public func start() {
        observationTask?.cancel()
        observationTask = Task {
            do {
                for try await rows in antiDeleteRepository.observeMessages(chatId: chat.chatId, limit: 300) {
                    self.messages = rows
                }
            } catch {}
        }

        Task {
            self.chatStealthRule = try? await stealthRepository.fetchChatRule(for: chat.chatId)
            if let remoteHistory = try? await transport.fetchMessageHistory(chatId: chat.chatId, fromMessageId: 0, limit: 80) {
                try? await antiDeleteRepository.upsertMessages(remoteHistory)
                // Вызываем viewMessages через StealthInterceptor: при «Нечитайке» он заблокируется
                let ids = remoteHistory.map(\.messageId)
                if !ids.isEmpty {
                    try? await transport.viewMessages(chatId: chat.chatId, messageIds: ids, forceRead: false)
                }
            }
        }
    }

    public func stop() {
        observationTask?.cancel()
        observationTask = nil
    }

    public func sendCurrentMessage() {
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let finalPayload: String
        if let quote = quotedExcerpt, !quote.isEmpty {
            finalPayload = "> \(quote)\n\n\(trimmed)"
        } else {
            finalPayload = trimmed
        }

        let replyId = replyTarget?.messageId
        composerText = ""
        replyTarget = nil
        quotedExcerpt = nil

        Task {
            if let sent = try? await transport.sendTextMessage(
                chatId: chat.chatId,
                text: finalPayload,
                replyToMessageId: replyId
            ) {
                try? await antiDeleteRepository.upsertMessage(sent)
            }
        }
    }

    public func notifyTyping() {
        Task {
            try? await transport.sendChatAction(chatId: chat.chatId, action: .typing)
        }
    }

    public func markAllReadManually() {
        let ids = messages.map(\.messageId)
        guard !ids.isEmpty else { return }
        Task {
            try? await transport.viewMessages(chatId: chat.chatId, messageIds: ids, forceRead: true)
            showToast("Отмечено прочитанным вручную")
        }
    }

    public func copyMessageText(_ message: CachedMessageRecord) {
        let content = message.text.isEmpty ? (message.caption ?? "") : message.text
        guard !content.isEmpty else { return }
        UIPasteboard.general.string = content
        showToast("Скопировано в буфер (включая защищённый чат)")
    }

    public func quoteSelection(_ selectedText: String, from message: CachedMessageRecord) {
        replyTarget = message
        quotedExcerpt = selectedText
    }

    public func translateMessage(_ message: CachedMessageRecord, targetLanguage: String) {
        let sourceText = message.text.isEmpty ? (message.caption ?? "") : message.text
        guard !sourceText.isEmpty else { return }
        Task {
            if let translated = try? await transport.translateText(sourceText, toLanguageCode: targetLanguage) {
                translatedTexts[message.messageId] = translated
            }
        }
    }

    public func openEditHistory(for message: CachedMessageRecord) {
        Task {
            let revisions = (try? await antiDeleteRepository.fetchEditHistory(
                chatId: message.chatId,
                messageId: message.messageId
            )) ?? []
            self.editHistoryRevisions = revisions
            self.selectedEditHistoryMessage = message
        }
    }

    public func openViewOnceMedia(for message: CachedMessageRecord) {
        Task {
            if let cached = try? await antiDeleteRepository.fetchViewOnceMedia(
                chatId: message.chatId,
                messageId: message.messageId
            ) {
                self.selectedViewOnceRecord = cached
            } else {
                showToast("Одноразовый файл ещё загружается в локальный кеш")
            }
        }
    }

    public func updatePerChatStealthRule(_ mode: StealthChatOverrideMode?) {
        Task {
            if let mode {
                let rule = StealthChatRuleRecord(chatId: chat.chatId, mode: mode, note: chat.title)
                try? await stealthRepository.setChatRule(rule)
                self.chatStealthRule = rule
                showToast(mode == .forceGhostOn ? "Призрак включён для этого чата" : "Чат добавлен в белый список")
            } else {
                try? await stealthRepository.removeChatRule(for: chat.chatId)
                self.chatStealthRule = nil
                showToast("Используется глобальный режим Призрака")
            }
        }
    }

    private func showToast(_ text: String) {
        toastMessage = text
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            if toastMessage == text {
                toastMessage = nil
            }
        }
    }
}
