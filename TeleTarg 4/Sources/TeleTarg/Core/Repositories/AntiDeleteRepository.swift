import Foundation
import GRDB

public protocol AntiDeleteRepositoryProtocol: Sendable {
    func upsertMessage(_ message: CachedMessageRecord) async throws
    func upsertMessages(_ messages: [CachedMessageRecord]) async throws
    func markMessagesDeletedLocally(chatId: Int64, messageIds: [Int64], deletedAt: Date) async throws
    func recordMessageEdit(
        chatId: Int64,
        messageId: Int64,
        newText: String,
        newCaption: String?,
        newRawJSON: String,
        editedAt: Date
    ) async throws
    func fetchEditHistory(chatId: Int64, messageId: Int64) async throws -> [MessageEditRevisionRecord]
    func cacheViewOnceMedia(
        chatId: Int64,
        messageId: Int64,
        senderUserId: Int64,
        mediaType: MessageContentType,
        decryptedSourceURL: URL,
        mimeType: String,
        originalTTLSeconds: Int
    ) async throws -> ViewOnceMediaCacheRecord
    func fetchViewOnceMedia(chatId: Int64, messageId: Int64) async throws -> ViewOnceMediaCacheRecord?
    func fetchAllViewOnceMedia() async throws -> [ViewOnceMediaCacheRecord]
    func fetchMessages(chatId: Int64, limit: Int) async throws -> [CachedMessageRecord]
    func observeMessages(chatId: Int64, limit: Int) -> AsyncThrowingStream<[CachedMessageRecord], Error>
    func observeDeletedMessageCount(chatId: Int64) -> AsyncThrowingStream<Int, Error>
}

public final class AntiDeleteRepository: AntiDeleteRepositoryProtocol, Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func upsertMessage(_ message: CachedMessageRecord) async throws {
        try await database.dbWriter.write { db in
            // Сохраняем локальные флаги Anti-Delete, если сообщение уже было помечено удалённым
            if let existing = try CachedMessageRecord.fetchOne(
                db,
                sql: "SELECT * FROM cached_messages WHERE chat_id = ? AND message_id = ?",
                arguments: [message.chatId, message.messageId]
            ) {
                var merged = message
                merged.isDeletedLocally = existing.isDeletedLocally
                merged.deletedAt = existing.deletedAt
                merged.editCount = max(existing.editCount, message.editCount)
                if merged.localMediaPath == nil {
                    merged.localMediaPath = existing.localMediaPath
                }
                try merged.save(db)
            } else {
                try message.save(db)
            }
        }
    }

    public func upsertMessages(_ messages: [CachedMessageRecord]) async throws {
        guard !messages.isEmpty else { return }
        try await database.dbWriter.write { db in
            for message in messages {
                if let existing = try CachedMessageRecord.fetchOne(
                    db,
                    sql: "SELECT * FROM cached_messages WHERE chat_id = ? AND message_id = ?",
                    arguments: [message.chatId, message.messageId]
                ) {
                    var merged = message
                    merged.isDeletedLocally = existing.isDeletedLocally
                    merged.deletedAt = existing.deletedAt
                    merged.editCount = max(existing.editCount, message.editCount)
                    if merged.localMediaPath == nil {
                        merged.localMediaPath = existing.localMediaPath
                    }
                    try merged.save(db)
                } else {
                    try message.save(db)
                }
            }
        }
    }

    public func markMessagesDeletedLocally(
        chatId: Int64,
        messageIds: [Int64],
        deletedAt: Date = Date()
    ) async throws {
        guard !messageIds.isEmpty else { return }
        try await database.dbWriter.write { db in
            try CachedMessageRecord
                .filter(CachedMessageRecord.Columns.chatId == chatId)
                .filter(messageIds.contains(CachedMessageRecord.Columns.messageId))
                .filter(CachedMessageRecord.Columns.isDeletedLocally == false)
                .updateAll(
                    db,
                    CachedMessageRecord.Columns.isDeletedLocally.set(to: true),
                    CachedMessageRecord.Columns.deletedAt.set(to: deletedAt)
                )
        }
    }

    public func recordMessageEdit(
        chatId: Int64,
        messageId: Int64,
        newText: String,
        newCaption: String?,
        newRawJSON: String,
        editedAt: Date = Date()
    ) async throws {
        try await database.dbWriter.write { db in
            guard var current = try CachedMessageRecord.fetchOne(
                db,
                sql: "SELECT * FROM cached_messages WHERE chat_id = ? AND message_id = ?",
                arguments: [chatId, messageId]
            ) else { return }

            let hasContentChanged = current.text != newText || current.caption != newCaption
            guard hasContentChanged else { return }

            let nextRevisionIndex = current.editCount + 1
            var revision = MessageEditRevisionRecord(
                chatId: chatId,
                messageId: messageId,
                revisionIndex: nextRevisionIndex,
                previousText: current.text,
                previousCaption: current.caption,
                previousRawJSON: current.rawJSON,
                capturedAt: editedAt
            )
            try revision.insert(db)

            current.text = newText
            current.caption = newCaption
            current.rawJSON = newRawJSON
            current.editedAt = editedAt
            current.editCount = nextRevisionIndex
            try current.save(db)
        }
    }

    public func fetchEditHistory(chatId: Int64, messageId: Int64) async throws -> [MessageEditRevisionRecord] {
        try await database.dbReader.read { db in
            try MessageEditRevisionRecord
                .filter(MessageEditRevisionRecord.Columns.chatId == chatId)
                .filter(MessageEditRevisionRecord.Columns.messageId == messageId)
                .order(MessageEditRevisionRecord.Columns.revisionIndex.asc)
                .fetchAll(db)
        }
    }

    public func cacheViewOnceMedia(
        chatId: Int64,
        messageId: Int64,
        senderUserId: Int64,
        mediaType: MessageContentType,
        decryptedSourceURL: URL,
        mimeType: String,
        originalTTLSeconds: Int
    ) async throws -> ViewOnceMediaCacheRecord {
        let fm = FileManager.default
        let originalFileName = decryptedSourceURL.lastPathComponent
        let ext = decryptedSourceURL.pathExtension.isEmpty ? "bin" : decryptedSourceURL.pathExtension
        let safeName = "ttl_\(chatId)_\(messageId)_\(Int(Date().timeIntervalSince1970)).\(ext)"
        let destinationURL = database.mediaVaultDirectory.appendingPathComponent(safeName)

        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }
        try fm.copyItem(at: decryptedSourceURL, to: destinationURL)
        try? fm.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: destinationURL.path
        )

        let attrs = try fm.attributesOfItem(atPath: destinationURL.path)
        let sizeBytes = (attrs[.size] as? NSNumber)?.int64Value ?? 0

        let record = ViewOnceMediaCacheRecord(
            chatId: chatId,
            messageId: messageId,
            senderUserId: senderUserId,
            mediaType: mediaType,
            protectedLocalPath: destinationURL.path,
            originalFileName: originalFileName,
            mimeType: mimeType,
            fileSizeBytes: sizeBytes,
            originalTTLSeconds: originalTTLSeconds,
            cachedAt: Date()
        )

        try await database.dbWriter.write { db in
            try record.save(db)
            try CachedMessageRecord
                .filter(CachedMessageRecord.Columns.chatId == chatId)
                .filter(CachedMessageRecord.Columns.messageId == messageId)
                .updateAll(
                    db,
                    CachedMessageRecord.Columns.localMediaPath.set(to: destinationURL.path),
                    CachedMessageRecord.Columns.isViewOnce.set(to: true),
                    CachedMessageRecord.Columns.selfDestructSeconds.set(to: originalTTLSeconds)
                )
        }

        return record
    }

    public func fetchViewOnceMedia(chatId: Int64, messageId: Int64) async throws -> ViewOnceMediaCacheRecord? {
        try await database.dbReader.read { db in
            try ViewOnceMediaCacheRecord.fetchOne(
                db,
                sql: "SELECT * FROM view_once_media_cache WHERE chat_id = ? AND message_id = ?",
                arguments: [chatId, messageId]
            )
        }
    }

    public func fetchAllViewOnceMedia() async throws -> [ViewOnceMediaCacheRecord] {
        try await database.dbReader.read { db in
            try ViewOnceMediaCacheRecord
                .order(ViewOnceMediaCacheRecord.Columns.cachedAt.desc)
                .fetchAll(db)
        }
    }

    public func fetchMessages(chatId: Int64, limit: Int = 200) async throws -> [CachedMessageRecord] {
        try await database.dbReader.read { db in
            try CachedMessageRecord
                .filter(CachedMessageRecord.Columns.chatId == chatId)
                .order(CachedMessageRecord.Columns.sentAt.asc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func observeMessages(chatId: Int64, limit: Int = 200) -> AsyncThrowingStream<[CachedMessageRecord], Error> {
        let observation = ValueObservation.tracking { db in
            try CachedMessageRecord
                .filter(CachedMessageRecord.Columns.chatId == chatId)
                .order(CachedMessageRecord.Columns.sentAt.asc)
                .limit(limit)
                .fetchAll(db)
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await messages in observation.values(in: database.dbReader) {
                        continuation.yield(messages)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func observeDeletedMessageCount(chatId: Int64) -> AsyncThrowingStream<Int, Error> {
        let observation = ValueObservation.tracking { db in
            try CachedMessageRecord
                .filter(CachedMessageRecord.Columns.chatId == chatId)
                .filter(CachedMessageRecord.Columns.isDeletedLocally == true)
                .fetchCount(db)
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await count in observation.values(in: database.dbReader) {
                        continuation.yield(count)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
