import Foundation
import GRDB

public final class AppDatabase: Sendable {
    public let dbWriter: any DatabaseWriter
    public let mediaVaultDirectory: URL
    public let avatarOverridesDirectory: URL

    public var dbReader: any DatabaseReader { dbWriter }

    public init(
        dbWriter: any DatabaseWriter,
        mediaVaultDirectory: URL,
        avatarOverridesDirectory: URL
    ) throws {
        self.dbWriter = dbWriter
        self.mediaVaultDirectory = mediaVaultDirectory
        self.avatarOverridesDirectory = avatarOverridesDirectory
        try Self.ensureDirectoryExists(mediaVaultDirectory)
        try Self.ensureDirectoryExists(avatarOverridesDirectory)
        try Self.migrator.migrate(dbWriter)
    }

    public static func makePersistent() throws -> AppDatabase {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let rootDir = appSupport.appendingPathComponent("TeleTarg", isDirectory: true)
        try ensureDirectoryExists(rootDir)

        let dbURL = rootDir.appendingPathComponent("teletarg_local.sqlite")
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
            try db.execute(sql: "PRAGMA busy_timeout = 5000")
        }

        let dbPool = try DatabasePool(path: dbURL.path, configuration: config)
        try fm.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: dbURL.path
        )

        return try AppDatabase(
            dbWriter: dbPool,
            mediaVaultDirectory: rootDir.appendingPathComponent("ViewOnceVault", isDirectory: true),
            avatarOverridesDirectory: rootDir.appendingPathComponent("AvatarOverrides", isDirectory: true)
        )
    }

    public static func makeInMemory() throws -> AppDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let dbQueue = try DatabaseQueue(configuration: config)
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TeleTargTests_\(UUID().uuidString)", isDirectory: true)
        return try AppDatabase(
            dbWriter: dbQueue,
            mediaVaultDirectory: tempRoot.appendingPathComponent("ViewOnceVault", isDirectory: true),
            avatarOverridesDirectory: tempRoot.appendingPathComponent("AvatarOverrides", isDirectory: true)
        )
    }

    private static func ensureDirectoryExists(_ url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        try? fm.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    // MARK: - GRDB Migrations

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial_teletarg_schema") { db in
            // 1. profile_overrides
            try db.create(table: ProfileOverrideRecord.databaseTableName) { t in
                t.primaryKey("user_id", .integer)
                t.column("first_name", .text)
                t.column("last_name", .text)
                t.column("username", .text)
                t.column("avatar_local_path", .text)
                t.column("avatar_is_video", .boolean)
                t.column("bio", .text)
                t.column("activity_status_mode", .text)
                t.column("activity_status_text", .text)
                t.column("name_color_hex", .text)
                t.column("header_color_hex", .text)
                t.column("badges_json", .text)
                t.column("emoji_status", .text)
                t.column("private_note", .text)
                t.column("updated_at", .datetime).notNull()
            }

            // 2. cached_messages (Anti-Delete + Edit Tracking + Raw Metadata)
            try db.create(table: CachedMessageRecord.databaseTableName) { t in
                t.column("chat_id", .integer).notNull()
                t.column("message_id", .integer).notNull()
                t.column("sender_user_id", .integer).notNull()
                t.column("reply_to_message_id", .integer)
                t.column("thread_topic_id", .integer)
                t.column("content_type", .text).notNull()
                t.column("text", .text).notNull().defaults(to: "")
                t.column("caption", .text)
                t.column("local_media_path", .text)
                t.column("media_mime_type", .text)
                t.column("media_file_size", .integer)
                t.column("is_outgoing", .boolean).notNull().defaults(to: false)
                t.column("is_read_by_peer", .boolean).notNull().defaults(to: false)
                t.column("is_protected_content", .boolean).notNull().defaults(to: false)
                t.column("is_view_once", .boolean).notNull().defaults(to: false)
                t.column("self_destruct_seconds", .integer)
                t.column("sent_at", .datetime).notNull()
                t.column("edited_at", .datetime)
                t.column("edit_count", .integer).notNull().defaults(to: 0)
                t.column("is_deleted_locally", .boolean).notNull().defaults(to: false)
                t.column("deleted_at", .datetime)
                t.column("reactions_json", .text)
                t.column("raw_json", .text).notNull().defaults(to: "{}")
                t.primaryKey(["chat_id", "message_id"])
            }
            try db.create(
                index: "idx_cached_messages_chat_sent",
                on: CachedMessageRecord.databaseTableName,
                columns: ["chat_id", "sent_at"]
            )
            try db.create(
                index: "idx_cached_messages_chat_deleted",
                on: CachedMessageRecord.databaseTableName,
                columns: ["chat_id", "is_deleted_locally"]
            )

            // 3. message_edit_revisions
            try db.create(table: MessageEditRevisionRecord.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("chat_id", .integer).notNull()
                t.column("message_id", .integer).notNull()
                t.column("revision_index", .integer).notNull()
                t.column("previous_text", .text).notNull()
                t.column("previous_caption", .text)
                t.column("previous_raw_json", .text).notNull().defaults(to: "{}")
                t.column("captured_at", .datetime).notNull()
                t.foreignKey(
                    ["chat_id", "message_id"],
                    references: CachedMessageRecord.databaseTableName,
                    columns: ["chat_id", "message_id"],
                    onDelete: .cascade
                )
            }
            try db.create(
                index: "idx_edit_revisions_lookup",
                on: MessageEditRevisionRecord.databaseTableName,
                columns: ["chat_id", "message_id", "revision_index"]
            )

            // 4. view_once_media_cache
            try db.create(table: ViewOnceMediaCacheRecord.databaseTableName) { t in
                t.column("chat_id", .integer).notNull()
                t.column("message_id", .integer).notNull()
                t.column("sender_user_id", .integer).notNull()
                t.column("media_type", .text).notNull()
                t.column("protected_local_path", .text).notNull()
                t.column("original_file_name", .text).notNull()
                t.column("mime_type", .text).notNull()
                t.column("file_size_bytes", .integer).notNull()
                t.column("original_ttl_seconds", .integer).notNull()
                t.column("cached_at", .datetime).notNull()
                t.primaryKey(["chat_id", "message_id"])
            }
            try db.create(
                index: "idx_view_once_cached_at",
                on: ViewOnceMediaCacheRecord.databaseTableName,
                columns: ["cached_at"]
            )

            // 5. stealth_settings (singleton row id = 1)
            try db.create(table: StealthSettingsRecord.databaseTableName) { t in
                t.primaryKey("id", .integer)
                t.column("is_master_ghost_enabled", .boolean).notNull().defaults(to: false)
                t.column("block_read_receipts", .boolean).notNull().defaults(to: true)
                t.column("block_typing_and_activities", .boolean).notNull().defaults(to: true)
                t.column("hide_online_presence", .boolean).notNull().defaults(to: true)
                t.column("auto_offline_after_send", .boolean).notNull().defaults(to: true)
                t.column("incognito_stories", .boolean).notNull().defaults(to: true)
                t.column("bypass_forward_restrictions", .boolean).notNull().defaults(to: true)
                t.column("updated_at", .datetime).notNull()
            }
            try StealthSettingsRecord.default.insert(db)

            // 6. stealth_chat_rules (whitelist / blacklist)
            try db.create(table: StealthChatRuleRecord.databaseTableName) { t in
                t.primaryKey("chat_id", .integer)
                t.column("mode", .text).notNull()
                t.column("note", .text)
                t.column("updated_at", .datetime).notNull()
            }

            // 7. app_settings (singleton row id = 1)
            try db.create(table: AppSettingsRecord.databaseTableName) { t in
                t.primaryKey("id", .integer)
                t.column("layout_mode", .text).notNull().defaults(to: AppLayoutMode.classic.rawValue)
                t.column("discord_palette", .text).notNull().defaults(to: DiscordThemePalette.onyx.rawValue)
                t.column("custom_accent_hex", .text).notNull().defaults(to: "#5865F2")
                t.column("font_family", .text).notNull().defaults(to: AppFontFamily.systemSF.rawValue)
                t.column("font_size_scale", .double).notNull().defaults(to: 1.0)
                t.column("show_user_and_chat_ids", .boolean).notNull().defaults(to: true)
                t.column("translation_target_language", .text).notNull().defaults(to: "ru")
                t.column("biometrics_enabled", .boolean).notNull().defaults(to: false)
                t.column("decoy_pin_enabled", .boolean).notNull().defaults(to: false)
                t.column("updated_at", .datetime).notNull()
            }
            try AppSettingsRecord.default.insert(db)

            // 8. hidden_chats
            try db.create(table: HiddenChatRecord.databaseTableName) { t in
                t.primaryKey("chat_id", .integer)
                t.column("is_decoy_visible", .boolean).notNull().defaults(to: false)
                t.column("hidden_at", .datetime).notNull()
            }
            try db.create(
                index: "idx_hidden_chats_decoy",
                on: HiddenChatRecord.databaseTableName,
                columns: ["is_decoy_visible"]
            )

            // 9. discord_server_mappings
            try db.create(table: DiscordServerMappingRecord.databaseTableName) { t in
                t.primaryKey("folder_or_chat_id", .text)
                t.column("display_title", .text).notNull()
                t.column("custom_icon_name", .text)
                t.column("custom_color_hex", .text)
                t.column("sort_order", .integer).notNull().defaults(to: 0)
            }
            try db.create(
                index: "idx_discord_servers_order",
                on: DiscordServerMappingRecord.databaseTableName,
                columns: ["sort_order"]
            )
        }

        return migrator
    }
}
