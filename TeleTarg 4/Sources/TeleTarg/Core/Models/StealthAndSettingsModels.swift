import Foundation
import GRDB

// MARK: - Stealth Mode Settings & Per-Chat Exceptions

public struct StealthSettingsRecord: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "stealth_settings"
    public static let singletonId: Int64 = 1

    public var id: Int64 = StealthSettingsRecord.singletonId
    public var isMasterGhostEnabled: Bool
    public var blockReadReceipts: Bool
    public var blockTypingAndActivities: Bool
    public var hideOnlinePresence: Bool
    public var autoOfflineAfterSend: Bool
    public var incognitoStories: Bool
    public var bypassForwardRestrictions: Bool
    public var updatedAt: Date

    public enum Columns: String, ColumnExpression {
        case id = "id"
        case isMasterGhostEnabled = "is_master_ghost_enabled"
        case blockReadReceipts = "block_read_receipts"
        case blockTypingAndActivities = "block_typing_and_activities"
        case hideOnlinePresence = "hide_online_presence"
        case autoOfflineAfterSend = "auto_offline_after_send"
        case incognitoStories = "incognito_stories"
        case bypassForwardRestrictions = "bypass_forward_restrictions"
        case updatedAt = "updated_at"
    }

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case isMasterGhostEnabled = "is_master_ghost_enabled"
        case blockReadReceipts = "block_read_receipts"
        case blockTypingAndActivities = "block_typing_and_activities"
        case hideOnlinePresence = "hide_online_presence"
        case autoOfflineAfterSend = "auto_offline_after_send"
        case incognitoStories = "incognito_stories"
        case bypassForwardRestrictions = "bypass_forward_restrictions"
        case updatedAt = "updated_at"
    }

    public static let `default` = StealthSettingsRecord(
        isMasterGhostEnabled: false,
        blockReadReceipts: true,
        blockTypingAndActivities: true,
        hideOnlinePresence: true,
        autoOfflineAfterSend: true,
        incognitoStories: true,
        bypassForwardRestrictions: true,
        updatedAt: Date()
    )

    public init(
        id: Int64 = StealthSettingsRecord.singletonId,
        isMasterGhostEnabled: Bool,
        blockReadReceipts: Bool,
        blockTypingAndActivities: Bool,
        hideOnlinePresence: Bool,
        autoOfflineAfterSend: Bool,
        incognitoStories: Bool,
        bypassForwardRestrictions: Bool,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.isMasterGhostEnabled = isMasterGhostEnabled
        self.blockReadReceipts = blockReadReceipts
        self.blockTypingAndActivities = blockTypingAndActivities
        self.hideOnlinePresence = hideOnlinePresence
        self.autoOfflineAfterSend = autoOfflineAfterSend
        self.incognitoStories = incognitoStories
        self.bypassForwardRestrictions = bypassForwardRestrictions
        self.updatedAt = updatedAt
    }
}

public enum StealthChatOverrideMode: String, Codable, Hashable, Sendable, CaseIterable {
    /// Принудительно включить режим «Призрак» в этом чате, даже если глобально он выключен
    case forceGhostOn
    /// Принудительно выключить режим «Призрак» в этом чате (белый список)
    case forceGhostOff
}

public struct StealthChatRuleRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "stealth_chat_rules"

    public let chatId: Int64
    public var mode: StealthChatOverrideMode
    public var note: String?
    public var updatedAt: Date

    public var id: Int64 { chatId }

    public enum Columns: String, ColumnExpression {
        case chatId = "chat_id"
        case mode = "mode"
        case note = "note"
        case updatedAt = "updated_at"
    }

    enum CodingKeys: String, CodingKey {
        case chatId = "chat_id"
        case mode = "mode"
        case note = "note"
        case updatedAt = "updated_at"
    }

    public init(
        chatId: Int64,
        mode: StealthChatOverrideMode,
        note: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.chatId = chatId
        self.mode = mode
        self.note = note
        self.updatedAt = updatedAt
    }
}

public struct EffectiveStealthPolicy: Hashable, Sendable {
    public let isGhostActive: Bool
    public let blockReadReceipts: Bool
    public let blockTypingAndActivities: Bool
    public let hideOnlinePresence: Bool
    public let autoOfflineAfterSend: Bool
    public let incognitoStories: Bool
    public let bypassForwardRestrictions: Bool

    public static func resolve(
        global: StealthSettingsRecord,
        chatRule: StealthChatRuleRecord?
    ) -> EffectiveStealthPolicy {
        let isActive: Bool
        switch chatRule?.mode {
        case .forceGhostOn:
            isActive = true
        case .forceGhostOff:
            isActive = false
        case .none:
            isActive = global.isMasterGhostEnabled
        }

        return EffectiveStealthPolicy(
            isGhostActive: isActive,
            blockReadReceipts: isActive && global.blockReadReceipts,
            blockTypingAndActivities: isActive && global.blockTypingAndActivities,
            hideOnlinePresence: isActive && global.hideOnlinePresence,
            autoOfflineAfterSend: isActive && global.autoOfflineAfterSend,
            incognitoStories: isActive && global.incognitoStories,
            bypassForwardRestrictions: global.bypassForwardRestrictions
        )
    }
}

// MARK: - App Layout Mode & Appearance Settings

public enum AppLayoutMode: String, Codable, Hashable, Sendable, CaseIterable {
    case classic
    case discord

    public var displayTitle: String {
        switch self {
        case .classic: return "Классический iOS"
        case .discord: return "Discord-стиль"
        }
    }
}

public enum DiscordThemePalette: String, Codable, Hashable, Sendable, CaseIterable {
    case onyx
    case ash
    case blurple
    case custom
}

public enum AppFontFamily: String, Codable, Hashable, Sendable, CaseIterable {
    case systemSF
    case roundedSF
    case monoSF
    case serifNewYork
}

public struct AppSettingsRecord: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "app_settings"
    public static let singletonId: Int64 = 1

    public var id: Int64 = AppSettingsRecord.singletonId
    public var layoutMode: AppLayoutMode
    public var discordPalette: DiscordThemePalette
    public var customAccentHex: String
    public var fontFamily: AppFontFamily
    public var fontSizeScale: Double
    public var showUserAndChatIDs: Bool
    public var translationTargetLanguage: String
    public var biometricsEnabled: Bool
    public var decoyPinEnabled: Bool
    public var updatedAt: Date

    public enum Columns: String, ColumnExpression {
        case id = "id"
        case layoutMode = "layout_mode"
        case discordPalette = "discord_palette"
        case customAccentHex = "custom_accent_hex"
        case fontFamily = "font_family"
        case fontSizeScale = "font_size_scale"
        case showUserAndChatIDs = "show_user_and_chat_ids"
        case translationTargetLanguage = "translation_target_language"
        case biometricsEnabled = "biometrics_enabled"
        case decoyPinEnabled = "decoy_pin_enabled"
        case updatedAt = "updated_at"
    }

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case layoutMode = "layout_mode"
        case discordPalette = "discord_palette"
        case customAccentHex = "custom_accent_hex"
        case fontFamily = "font_family"
        case fontSizeScale = "font_size_scale"
        case showUserAndChatIDs = "show_user_and_chat_ids"
        case translationTargetLanguage = "translation_target_language"
        case biometricsEnabled = "biometrics_enabled"
        case decoyPinEnabled = "decoy_pin_enabled"
        case updatedAt = "updated_at"
    }

    public static let `default` = AppSettingsRecord(
        layoutMode: .classic,
        discordPalette: .onyx,
        customAccentHex: "#5865F2",
        fontFamily: .systemSF,
        fontSizeScale: 1.0,
        showUserAndChatIDs: true,
        translationTargetLanguage: "ru",
        biometricsEnabled: false,
        decoyPinEnabled: false,
        updatedAt: Date()
    )

    public init(
        id: Int64 = AppSettingsRecord.singletonId,
        layoutMode: AppLayoutMode,
        discordPalette: DiscordThemePalette,
        customAccentHex: String,
        fontFamily: AppFontFamily,
        fontSizeScale: Double,
        showUserAndChatIDs: Bool,
        translationTargetLanguage: String,
        biometricsEnabled: Bool,
        decoyPinEnabled: Bool,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.layoutMode = layoutMode
        self.discordPalette = discordPalette
        self.customAccentHex = customAccentHex
        self.fontFamily = fontFamily
        self.fontSizeScale = fontSizeScale
        self.showUserAndChatIDs = showUserAndChatIDs
        self.translationTargetLanguage = translationTargetLanguage
        self.biometricsEnabled = biometricsEnabled
        self.decoyPinEnabled = decoyPinEnabled
        self.updatedAt = updatedAt
    }
}

// MARK: - Hidden Chats & Discord Server Mapping

public struct HiddenChatRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "hidden_chats"

    public let chatId: Int64
    public var isDecoyVisible: Bool
    public var hiddenAt: Date

    public var id: Int64 { chatId }

    public enum Columns: String, ColumnExpression {
        case chatId = "chat_id"
        case isDecoyVisible = "is_decoy_visible"
        case hiddenAt = "hidden_at"
    }

    enum CodingKeys: String, CodingKey {
        case chatId = "chat_id"
        case isDecoyVisible = "is_decoy_visible"
        case hiddenAt = "hidden_at"
    }

    public init(chatId: Int64, isDecoyVisible: Bool = false, hiddenAt: Date = Date()) {
        self.chatId = chatId
        self.isDecoyVisible = isDecoyVisible
        self.hiddenAt = hiddenAt
    }
}

public struct DiscordServerMappingRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "discord_server_mappings"

    public let folderOrChatId: String
    public var displayTitle: String
    public var customIconName: String?
    public var customColorHex: String?
    public var sortOrder: Int

    public var id: String { folderOrChatId }

    public enum Columns: String, ColumnExpression {
        case folderOrChatId = "folder_or_chat_id"
        case displayTitle = "display_title"
        case customIconName = "custom_icon_name"
        case customColorHex = "custom_color_hex"
        case sortOrder = "sort_order"
    }

    enum CodingKeys: String, CodingKey {
        case folderOrChatId = "folder_or_chat_id"
        case displayTitle = "display_title"
        case customIconName = "custom_icon_name"
        case customColorHex = "custom_color_hex"
        case sortOrder = "sort_order"
    }

    public init(
        folderOrChatId: String,
        displayTitle: String,
        customIconName: String? = nil,
        customColorHex: String? = nil,
        sortOrder: Int
    ) {
        self.folderOrChatId = folderOrChatId
        self.displayTitle = displayTitle
        self.customIconName = customIconName
        self.customColorHex = customColorHex
        self.sortOrder = sortOrder
    }
}
