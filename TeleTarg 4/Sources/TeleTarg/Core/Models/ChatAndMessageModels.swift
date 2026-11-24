import Foundation
import GRDB

// MARK: - Chat & Message Domain Enums

public enum ChatKind: String, Codable, Hashable, Sendable {
    case privateChat
    case basicGroup
    case supergroup
    case forum
    case channel
    case secretChat
}

public enum MessageContentType: String, Codable, Hashable, Sendable {
    case text
    case photo
    case video
    case videoNote
    case voiceNote
    case document
    case audio
    case sticker
    case animation
    case poll
    case call
    case service
    case unsupported
}

public struct MessageReaction: Codable, Hashable, Sendable {
    public let emoji: String
    public var count: Int
    public var isChosenByMe: Bool

    public init(emoji: String, count: Int, isChosenByMe: Bool) {
        self.emoji = emoji
        self.count = count
        self.isChosenByMe = isChosenByMe
    }
}

// MARK: - Cached Message Record (GRDB Table: cached_messages)

public struct CachedMessageRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "cached_messages"

    public let chatId: Int64
    public let messageId: Int64
    public let senderUserId: Int64
    public let replyToMessageId: Int64?
    public let threadTopicId: Int64?
    public var contentType: MessageContentType
    public var text: String
    public var caption: String?
    public var localMediaPath: String?
    public var mediaMimeType: String?
    public var mediaFileSize: Int64?
    public var isOutgoing: Bool
    public var isReadByPeer: Bool
    public var isProtectedContent: Bool
    public var isViewOnce: Bool
    public var selfDestructSeconds: Int?
    public var sentAt: Date
    public var editedAt: Date?
    public var editCount: Int
    public var isDeletedLocally: Bool
    public var deletedAt: Date?
    public var reactionsJSON: String?
    public var rawJSON: String

    public var id: String { "\(chatId)_\(messageId)" }

    public enum Columns: String, ColumnExpression {
        case chatId = "chat_id"
        case messageId = "message_id"
        case senderUserId = "sender_user_id"
        case replyToMessageId = "reply_to_message_id"
        case threadTopicId = "thread_topic_id"
        case contentType = "content_type"
        case text = "text"
        case caption = "caption"
        case localMediaPath = "local_media_path"
        case mediaMimeType = "media_mime_type"
        case mediaFileSize = "media_file_size"
        case isOutgoing = "is_outgoing"
        case isReadByPeer = "is_read_by_peer"
        case isProtectedContent = "is_protected_content"
        case isViewOnce = "is_view_once"
        case selfDestructSeconds = "self_destruct_seconds"
        case sentAt = "sent_at"
        case editedAt = "edited_at"
        case editCount = "edit_count"
        case isDeletedLocally = "is_deleted_locally"
        case deletedAt = "deleted_at"
        case reactionsJSON = "reactions_json"
        case rawJSON = "raw_json"
    }

    enum CodingKeys: String, CodingKey {
        case chatId = "chat_id"
        case messageId = "message_id"
        case senderUserId = "sender_user_id"
        case replyToMessageId = "reply_to_message_id"
        case threadTopicId = "thread_topic_id"
        case contentType = "content_type"
        case text = "text"
        case caption = "caption"
        case localMediaPath = "local_media_path"
        case mediaMimeType = "media_mime_type"
        case mediaFileSize = "media_file_size"
        case isOutgoing = "is_outgoing"
        case isReadByPeer = "is_read_by_peer"
        case isProtectedContent = "is_protected_content"
        case isViewOnce = "is_view_once"
        case selfDestructSeconds = "self_destruct_seconds"
        case sentAt = "sent_at"
        case editedAt = "edited_at"
        case editCount = "edit_count"
        case isDeletedLocally = "is_deleted_locally"
        case deletedAt = "deleted_at"
        case reactionsJSON = "reactions_json"
        case rawJSON = "raw_json"
    }

    public init(
        chatId: Int64,
        messageId: Int64,
        senderUserId: Int64,
        replyToMessageId: Int64? = nil,
        threadTopicId: Int64? = nil,
        contentType: MessageContentType,
        text: String,
        caption: String? = nil,
        localMediaPath: String? = nil,
        mediaMimeType: String? = nil,
        mediaFileSize: Int64? = nil,
        isOutgoing: Bool,
        isReadByPeer: Bool = false,
        isProtectedContent: Bool = false,
        isViewOnce: Bool = false,
        selfDestructSeconds: Int? = nil,
        sentAt: Date,
        editedAt: Date? = nil,
        editCount: Int = 0,
        isDeletedLocally: Bool = false,
        deletedAt: Date? = nil,
        reactions: [MessageReaction] = [],
        rawJSON: String = "{}"
    ) {
        self.chatId = chatId
        self.messageId = messageId
        self.senderUserId = senderUserId
        self.replyToMessageId = replyToMessageId
        self.threadTopicId = threadTopicId
        self.contentType = contentType
        self.text = text
        self.caption = caption
        self.localMediaPath = localMediaPath
        self.mediaMimeType = mediaMimeType
        self.mediaFileSize = mediaFileSize
        self.isOutgoing = isOutgoing
        self.isReadByPeer = isReadByPeer
        self.isProtectedContent = isProtectedContent
        self.isViewOnce = isViewOnce
        self.selfDestructSeconds = selfDestructSeconds
        self.sentAt = sentAt
        self.editedAt = editedAt
        self.editCount = editCount
        self.isDeletedLocally = isDeletedLocally
        self.deletedAt = deletedAt
        self.reactionsJSON = Self.encodeReactions(reactions)
        self.rawJSON = rawJSON
    }

    public var decodedReactions: [MessageReaction] {
        guard let reactionsJSON, let data = reactionsJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([MessageReaction].self, from: data)) ?? []
    }

    public var deletedBadgeText: String? {
        guard isDeletedLocally, let deletedAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "Удалено в \(formatter.string(from: deletedAt))"
    }

    private static func encodeReactions(_ reactions: [MessageReaction]) -> String? {
        guard !reactions.isEmpty, let data = try? JSONEncoder().encode(reactions) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Message Edit Revision Record (GRDB Table: message_edit_revisions)

public struct MessageEditRevisionRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "message_edit_revisions"

    public var id: Int64?
    public let chatId: Int64
    public let messageId: Int64
    public let revisionIndex: Int
    public let previousText: String
    public let previousCaption: String?
    public let previousRawJSON: String
    public let capturedAt: Date

    public enum Columns: String, ColumnExpression {
        case id = "id"
        case chatId = "chat_id"
        case messageId = "message_id"
        case revisionIndex = "revision_index"
        case previousText = "previous_text"
        case previousCaption = "previous_caption"
        case previousRawJSON = "previous_raw_json"
        case capturedAt = "captured_at"
    }

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case chatId = "chat_id"
        case messageId = "message_id"
        case revisionIndex = "revision_index"
        case previousText = "previous_text"
        case previousCaption = "previous_caption"
        case previousRawJSON = "previous_raw_json"
        case capturedAt = "captured_at"
    }

    public init(
        id: Int64? = nil,
        chatId: Int64,
        messageId: Int64,
        revisionIndex: Int,
        previousText: String,
        previousCaption: String? = nil,
        previousRawJSON: String = "{}",
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.chatId = chatId
        self.messageId = messageId
        self.revisionIndex = revisionIndex
        self.previousText = previousText
        self.previousCaption = previousCaption
        self.previousRawJSON = previousRawJSON
        self.capturedAt = capturedAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - View-Once / Self-Destruct Media Cache Record (GRDB Table: view_once_media_cache)

public struct ViewOnceMediaCacheRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "view_once_media_cache"

    public let chatId: Int64
    public let messageId: Int64
    public let senderUserId: Int64
    public let mediaType: MessageContentType
    public let protectedLocalPath: String
    public let originalFileName: String
    public let mimeType: String
    public let fileSizeBytes: Int64
    public let originalTTLSeconds: Int
    public let cachedAt: Date

    public var id: String { "\(chatId)_\(messageId)" }

    public enum Columns: String, ColumnExpression {
        case chatId = "chat_id"
        case messageId = "message_id"
        case senderUserId = "sender_user_id"
        case mediaType = "media_type"
        case protectedLocalPath = "protected_local_path"
        case originalFileName = "original_file_name"
        case mimeType = "mime_type"
        case fileSizeBytes = "file_size_bytes"
        case originalTTLSeconds = "original_ttl_seconds"
        case cachedAt = "cached_at"
    }

    enum CodingKeys: String, CodingKey {
        case chatId = "chat_id"
        case messageId = "message_id"
        case senderUserId = "sender_user_id"
        case mediaType = "media_type"
        case protectedLocalPath = "protected_local_path"
        case originalFileName = "original_file_name"
        case mimeType = "mime_type"
        case fileSizeBytes = "file_size_bytes"
        case originalTTLSeconds = "original_ttl_seconds"
        case cachedAt = "cached_at"
    }

    public init(
        chatId: Int64,
        messageId: Int64,
        senderUserId: Int64,
        mediaType: MessageContentType,
        protectedLocalPath: String,
        originalFileName: String,
        mimeType: String,
        fileSizeBytes: Int64,
        originalTTLSeconds: Int,
        cachedAt: Date = Date()
    ) {
        self.chatId = chatId
        self.messageId = messageId
        self.senderUserId = senderUserId
        self.mediaType = mediaType
        self.protectedLocalPath = protectedLocalPath
        self.originalFileName = originalFileName
        self.mimeType = mimeType
        self.fileSizeBytes = fileSizeBytes
        self.originalTTLSeconds = originalTTLSeconds
        self.cachedAt = cachedAt
    }
}
