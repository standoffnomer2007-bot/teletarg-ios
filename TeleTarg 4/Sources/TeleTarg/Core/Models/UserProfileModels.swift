import Foundation
import GRDB

// MARK: - Profile Badges & Status Types

public enum ProfileBadge: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case verified
    case premium
    case developer
    case bot
    case scam
    case fake
    case customStar

    public var id: String { rawValue }

    public var systemSymbolName: String {
        switch self {
        case .verified: return "checkmark.seal.fill"
        case .premium: return "star.circle.fill"
        case .developer: return "hammer.circle.fill"
        case .bot: return "cpu.fill"
        case .scam: return "exclamationmark.triangle.fill"
        case .fake: return "eye.slash.circle.fill"
        case .customStar: return "sparkles"
        }
    }

    public var displayTitle: String {
        switch self {
        case .verified: return "Верификация"
        case .premium: return "Премиум"
        case .developer: return "Разработчик"
        case .bot: return "Бот"
        case .scam: return "Предупреждение"
        case .fake: return "Фейк"
        case .customStar: return "Особый статус"
        }
    }
}

public enum ActivityStatusMode: String, Codable, Hashable, Sendable, CaseIterable {
    case remote
    case online
    case offline
    case recently
    case customText
}

public enum ProfileOverrideField: String, Codable, Hashable, Sendable, CaseIterable {
    case firstName
    case lastName
    case username
    case avatarLocalPath
    case bio
    case activityStatus
    case nameColorHex
    case headerColorHex
    case badges
    case emojiStatus
    case privateNote
}

// MARK: - Remote User Profile (Source from Telegram / Transport)

public struct RemoteUserProfile: Codable, Hashable, Sendable, Identifiable {
    public let userId: Int64
    public var firstName: String
    public var lastName: String
    public var username: String?
    public var phoneNumber: String?
    public var avatarLocalPath: String?
    public var avatarIsVideo: Bool
    public var bio: String?
    public var isOnline: Bool
    public var lastSeenDate: Date?
    public var statusDescription: String
    public var nameColorHex: String?
    public var headerColorHex: String?
    public var badges: [ProfileBadge]
    public var emojiStatus: String?
    public var isChannelOrGroup: Bool

    public var id: Int64 { userId }

    public init(
        userId: Int64,
        firstName: String,
        lastName: String = "",
        username: String? = nil,
        phoneNumber: String? = nil,
        avatarLocalPath: String? = nil,
        avatarIsVideo: Bool = false,
        bio: String? = nil,
        isOnline: Bool = false,
        lastSeenDate: Date? = nil,
        statusDescription: String = "был(а) недавно",
        nameColorHex: String? = nil,
        headerColorHex: String? = nil,
        badges: [ProfileBadge] = [],
        emojiStatus: String? = nil,
        isChannelOrGroup: Bool = false
    ) {
        self.userId = userId
        self.firstName = firstName
        self.lastName = lastName
        self.username = username
        self.phoneNumber = phoneNumber
        self.avatarLocalPath = avatarLocalPath
        self.avatarIsVideo = avatarIsVideo
        self.bio = bio
        self.isOnline = isOnline
        self.lastSeenDate = lastSeenDate
        self.statusDescription = statusDescription
        self.nameColorHex = nameColorHex
        self.headerColorHex = headerColorHex
        self.badges = badges
        self.emojiStatus = emojiStatus
        self.isChannelOrGroup = isChannelOrGroup
    }
}

// MARK: - Local Profile Override Record (GRDB Table: profile_overrides)

public struct ProfileOverrideRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "profile_overrides"

    public let userId: Int64
    public var firstName: String?
    public var lastName: String?
    public var username: String?
    public var avatarLocalPath: String?
    public var avatarIsVideo: Bool?
    public var bio: String?
    public var activityStatusMode: ActivityStatusMode?
    public var activityStatusText: String?
    public var nameColorHex: String?
    public var headerColorHex: String?
    public var badgesJSON: String?
    public var emojiStatus: String?
    public var privateNote: String?
    public var updatedAt: Date

    public var id: Int64 { userId }

    public enum Columns: String, ColumnExpression {
        case userId = "user_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case username = "username"
        case avatarLocalPath = "avatar_local_path"
        case avatarIsVideo = "avatar_is_video"
        case bio = "bio"
        case activityStatusMode = "activity_status_mode"
        case activityStatusText = "activity_status_text"
        case nameColorHex = "name_color_hex"
        case headerColorHex = "header_color_hex"
        case badgesJSON = "badges_json"
        case emojiStatus = "emoji_status"
        case privateNote = "private_note"
        case updatedAt = "updated_at"
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case username = "username"
        case avatarLocalPath = "avatar_local_path"
        case avatarIsVideo = "avatar_is_video"
        case bio = "bio"
        case activityStatusMode = "activity_status_mode"
        case activityStatusText = "activity_status_text"
        case nameColorHex = "name_color_hex"
        case headerColorHex = "header_color_hex"
        case badgesJSON = "badges_json"
        case emojiStatus = "emoji_status"
        case privateNote = "private_note"
        case updatedAt = "updated_at"
    }

    public init(
        userId: Int64,
        firstName: String? = nil,
        lastName: String? = nil,
        username: String? = nil,
        avatarLocalPath: String? = nil,
        avatarIsVideo: Bool? = nil,
        bio: String? = nil,
        activityStatusMode: ActivityStatusMode? = nil,
        activityStatusText: String? = nil,
        nameColorHex: String? = nil,
        headerColorHex: String? = nil,
        badges: [ProfileBadge]? = nil,
        emojiStatus: String? = nil,
        privateNote: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.userId = userId
        self.firstName = firstName
        self.lastName = lastName
        self.username = username
        self.avatarLocalPath = avatarLocalPath
        self.avatarIsVideo = avatarIsVideo
        self.bio = bio
        self.activityStatusMode = activityStatusMode
        self.activityStatusText = activityStatusText
        self.nameColorHex = nameColorHex
        self.headerColorHex = headerColorHex
        self.badgesJSON = Self.encodeBadges(badges)
        self.emojiStatus = emojiStatus
        self.privateNote = privateNote
        self.updatedAt = updatedAt
    }

    public var decodedBadges: [ProfileBadge]? {
        guard let badgesJSON, let data = badgesJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([ProfileBadge].self, from: data)
    }

    public mutating func setBadges(_ badges: [ProfileBadge]?) {
        self.badgesJSON = Self.encodeBadges(badges)
    }

    public var isEmpty: Bool {
        firstName == nil &&
        lastName == nil &&
        username == nil &&
        avatarLocalPath == nil &&
        avatarIsVideo == nil &&
        bio == nil &&
        activityStatusMode == nil &&
        activityStatusText == nil &&
        nameColorHex == nil &&
        headerColorHex == nil &&
        badgesJSON == nil &&
        emojiStatus == nil &&
        privateNote == nil
    }

    public mutating func reset(field: ProfileOverrideField) {
        switch field {
        case .firstName:
            firstName = nil
        case .lastName:
            lastName = nil
        case .username:
            username = nil
        case .avatarLocalPath:
            avatarLocalPath = nil
            avatarIsVideo = nil
        case .bio:
            bio = nil
        case .activityStatus:
            activityStatusMode = nil
            activityStatusText = nil
        case .nameColorHex:
            nameColorHex = nil
        case .headerColorHex:
            headerColorHex = nil
        case .badges:
            badgesJSON = nil
        case .emojiStatus:
            emojiStatus = nil
        case .privateNote:
            privateNote = nil
        }
        updatedAt = Date()
    }

    private static func encodeBadges(_ badges: [ProfileBadge]?) -> String? {
        guard let badges else { return nil }
        guard let data = try? JSONEncoder().encode(badges) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Effective Merged Profile (Consumed by All UI Screens)

public struct EffectiveUserProfile: Hashable, Sendable, Identifiable {
    public let userId: Int64
    public let firstName: String
    public let lastName: String
    public let username: String?
    public let phoneNumber: String?
    public let avatarLocalPath: String?
    public let avatarIsVideo: Bool
    public let bio: String?
    public let isOnline: Bool
    public let statusDescription: String
    public let nameColorHex: String?
    public let headerColorHex: String?
    public let badges: [ProfileBadge]
    public let emojiStatus: String?
    public let privateNote: String?
    public let overriddenFields: Set<ProfileOverrideField>
    public let isChannelOrGroup: Bool

    public var id: Int64 { userId }

    public var fullName: String {
        let joined = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return joined.isEmpty ? "ID \(userId)" : joined
    }

    public var formattedUsername: String? {
        guard let username, !username.isEmpty else { return nil }
        return username.hasPrefix("@") ? username : "@\(username)"
    }

    public var hasAnyLocalOverride: Bool {
        !overriddenFields.isEmpty
    }

    public static func merge(
        remote: RemoteUserProfile,
        override record: ProfileOverrideRecord?
    ) -> EffectiveUserProfile {
        guard let record else {
            return EffectiveUserProfile(
                userId: remote.userId,
                firstName: remote.firstName,
                lastName: remote.lastName,
                username: remote.username,
                phoneNumber: remote.phoneNumber,
                avatarLocalPath: remote.avatarLocalPath,
                avatarIsVideo: remote.avatarIsVideo,
                bio: remote.bio,
                isOnline: remote.isOnline,
                statusDescription: remote.statusDescription,
                nameColorHex: remote.nameColorHex,
                headerColorHex: remote.headerColorHex,
                badges: remote.badges,
                emojiStatus: remote.emojiStatus,
                privateNote: nil,
                overriddenFields: [],
                isChannelOrGroup: remote.isChannelOrGroup
            )
        }

        var overridden = Set<ProfileOverrideField>()

        let finalFirstName: String
        if let v = record.firstName {
            finalFirstName = v
            overridden.insert(.firstName)
        } else {
            finalFirstName = remote.firstName
        }

        let finalLastName: String
        if let v = record.lastName {
            finalLastName = v
            overridden.insert(.lastName)
        } else {
            finalLastName = remote.lastName
        }

        let finalUsername: String?
        if let v = record.username {
            finalUsername = v
            overridden.insert(.username)
        } else {
            finalUsername = remote.username
        }

        let finalAvatarPath: String?
        let finalAvatarIsVideo: Bool
        if let path = record.avatarLocalPath {
            finalAvatarPath = path
            finalAvatarIsVideo = record.avatarIsVideo ?? false
            overridden.insert(.avatarLocalPath)
        } else {
            finalAvatarPath = remote.avatarLocalPath
            finalAvatarIsVideo = remote.avatarIsVideo
        }

        let finalBio: String?
        if let v = record.bio {
            finalBio = v
            overridden.insert(.bio)
        } else {
            finalBio = remote.bio
        }

        let finalIsOnline: Bool
        let finalStatusDescription: String
        if let mode = record.activityStatusMode, mode != .remote {
            overridden.insert(.activityStatus)
            switch mode {
            case .remote:
                finalIsOnline = remote.isOnline
                finalStatusDescription = remote.statusDescription
            case .online:
                finalIsOnline = true
                finalStatusDescription = "в сети"
            case .offline:
                finalIsOnline = false
                finalStatusDescription = "не в сети"
            case .recently:
                finalIsOnline = false
                finalStatusDescription = "был(а) недавно"
            case .customText:
                finalIsOnline = false
                finalStatusDescription = record.activityStatusText?.isEmpty == false
                    ? (record.activityStatusText ?? remote.statusDescription)
                    : remote.statusDescription
            }
        } else {
            finalIsOnline = remote.isOnline
            finalStatusDescription = remote.statusDescription
        }

        let finalNameColor: String?
        if let v = record.nameColorHex {
            finalNameColor = v
            overridden.insert(.nameColorHex)
        } else {
            finalNameColor = remote.nameColorHex
        }

        let finalHeaderColor: String?
        if let v = record.headerColorHex {
            finalHeaderColor = v
            overridden.insert(.headerColorHex)
        } else {
            finalHeaderColor = remote.headerColorHex
        }

        let finalBadges: [ProfileBadge]
        if let decoded = record.decodedBadges {
            finalBadges = decoded
            overridden.insert(.badges)
        } else {
            finalBadges = remote.badges
        }

        let finalEmojiStatus: String?
        if let v = record.emojiStatus {
            finalEmojiStatus = v
            overridden.insert(.emojiStatus)
        } else {
            finalEmojiStatus = remote.emojiStatus
        }

        let finalNote = record.privateNote
        if let finalNote, !finalNote.isEmpty {
            overridden.insert(.privateNote)
        }

        return EffectiveUserProfile(
            userId: remote.userId,
            firstName: finalFirstName,
            lastName: finalLastName,
            username: finalUsername,
            phoneNumber: remote.phoneNumber,
            avatarLocalPath: finalAvatarPath,
            avatarIsVideo: finalAvatarIsVideo,
            bio: finalBio,
            isOnline: finalIsOnline,
            statusDescription: finalStatusDescription,
            nameColorHex: finalNameColor,
            headerColorHex: finalHeaderColor,
            badges: finalBadges,
            emojiStatus: finalEmojiStatus,
            privateNote: finalNote,
            overriddenFields: overridden,
            isChannelOrGroup: remote.isChannelOrGroup
        )
    }
}
