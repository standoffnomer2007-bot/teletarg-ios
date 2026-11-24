import Foundation
import GRDB

public protocol AppSettingsRepositoryProtocol: Sendable {
    func fetchSettings() async throws -> AppSettingsRecord
    func updateSettings(_ update: @Sendable (inout AppSettingsRecord) -> Void) async throws -> AppSettingsRecord
    func setLayoutMode(_ mode: AppLayoutMode) async throws
    func observeSettings() -> AsyncThrowingStream<AppSettingsRecord, Error>

    func fetchHiddenChats(decoyMode: Bool) async throws -> Set<Int64>
    func setChatHidden(chatId: Int64, hidden: Bool, decoyVisible: Bool) async throws
    func observeHiddenChatIds() -> AsyncThrowingStream<Set<Int64>, Error>

    func fetchDiscordServerMappings() async throws -> [DiscordServerMappingRecord]
    func saveDiscordServerMappings(_ mappings: [DiscordServerMappingRecord]) async throws
    func observeDiscordServerMappings() -> AsyncThrowingStream<[DiscordServerMappingRecord], Error>
}

public final class AppSettingsRepository: AppSettingsRepositoryProtocol, Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func fetchSettings() async throws -> AppSettingsRecord {
        try await database.dbReader.read { db in
            try AppSettingsRecord.fetchOne(db, key: AppSettingsRecord.singletonId) ?? .default
        }
    }

    @discardableResult
    public func updateSettings(
        _ update: @Sendable (inout AppSettingsRecord) -> Void
    ) async throws -> AppSettingsRecord {
        try await database.dbWriter.write { db in
            var record = try AppSettingsRecord.fetchOne(db, key: AppSettingsRecord.singletonId) ?? .default
            update(&record)
            record.id = AppSettingsRecord.singletonId
            record.updatedAt = Date()
            try record.save(db)
            return record
        }
    }

    public func setLayoutMode(_ mode: AppLayoutMode) async throws {
        _ = try await updateSettings { settings in
            settings.layoutMode = mode
        }
    }

    public func observeSettings() -> AsyncThrowingStream<AppSettingsRecord, Error> {
        let observation = ValueObservation.tracking { db in
            try AppSettingsRecord.fetchOne(db, key: AppSettingsRecord.singletonId) ?? .default
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await settings in observation.values(in: database.dbReader) {
                        continuation.yield(settings)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Hidden Chats

    public func fetchHiddenChats(decoyMode: Bool) async throws -> Set<Int64> {
        try await database.dbReader.read { db in
            let request: QueryInterfaceRequest<HiddenChatRecord>
            if decoyMode {
                request = HiddenChatRecord.filter(HiddenChatRecord.Columns.isDecoyVisible == true)
            } else {
                request = HiddenChatRecord.all()
            }
            let rows = try request.fetchAll(db)
            return Set(rows.map(\.chatId))
        }
    }

    public func setChatHidden(chatId: Int64, hidden: Bool, decoyVisible: Bool = false) async throws {
        try await database.dbWriter.write { db in
            if hidden {
                let record = HiddenChatRecord(chatId: chatId, isDecoyVisible: decoyVisible, hiddenAt: Date())
                try record.save(db)
            } else {
                _ = try HiddenChatRecord.deleteOne(db, key: chatId)
            }
        }
    }

    public func observeHiddenChatIds() -> AsyncThrowingStream<Set<Int64>, Error> {
        let observation = ValueObservation.tracking { db -> Set<Int64> in
            let rows = try HiddenChatRecord.fetchAll(db)
            return Set(rows.map(\.chatId))
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await ids in observation.values(in: database.dbReader) {
                        continuation.yield(ids)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Discord Server Rail Mappings

    public func fetchDiscordServerMappings() async throws -> [DiscordServerMappingRecord] {
        try await database.dbReader.read { db in
            try DiscordServerMappingRecord
                .order(DiscordServerMappingRecord.Columns.sortOrder.asc)
                .fetchAll(db)
        }
    }

    public func saveDiscordServerMappings(_ mappings: [DiscordServerMappingRecord]) async throws {
        try await database.dbWriter.write { db in
            try DiscordServerMappingRecord.deleteAll(db)
            for item in mappings {
                try item.insert(db)
            }
        }
    }

    public func observeDiscordServerMappings() -> AsyncThrowingStream<[DiscordServerMappingRecord], Error> {
        let observation = ValueObservation.tracking { db in
            try DiscordServerMappingRecord
                .order(DiscordServerMappingRecord.Columns.sortOrder.asc)
                .fetchAll(db)
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await items in observation.values(in: database.dbReader) {
                        continuation.yield(items)
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
