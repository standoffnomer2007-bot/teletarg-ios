import Foundation
import GRDB

public protocol StealthSettingsRepositoryProtocol: Sendable {
    func fetchGlobalSettings() async throws -> StealthSettingsRecord
    func updateGlobalSettings(_ update: @Sendable (inout StealthSettingsRecord) -> Void) async throws -> StealthSettingsRecord
    func toggleMasterGhostMode() async throws -> Bool
    func fetchChatRule(for chatId: Int64) async throws -> StealthChatRuleRecord?
    func fetchAllChatRules() async throws -> [StealthChatRuleRecord]
    func setChatRule(_ rule: StealthChatRuleRecord) async throws
    func removeChatRule(for chatId: Int64) async throws
    func effectivePolicy(for chatId: Int64?) async throws -> EffectiveStealthPolicy
    func observeGlobalSettings() -> AsyncThrowingStream<StealthSettingsRecord, Error>
    func observeAllChatRules() -> AsyncThrowingStream<[StealthChatRuleRecord], Error>
}

public final class StealthSettingsRepository: StealthSettingsRepositoryProtocol, Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func fetchGlobalSettings() async throws -> StealthSettingsRecord {
        try await database.dbReader.read { db in
            try StealthSettingsRecord.fetchOne(db, key: StealthSettingsRecord.singletonId) ?? .default
        }
    }

    @discardableResult
    public func updateGlobalSettings(
        _ update: @Sendable (inout StealthSettingsRecord) -> Void
    ) async throws -> StealthSettingsRecord {
        try await database.dbWriter.write { db in
            var record = try StealthSettingsRecord.fetchOne(db, key: StealthSettingsRecord.singletonId) ?? .default
            update(&record)
            record.id = StealthSettingsRecord.singletonId
            record.updatedAt = Date()
            try record.save(db)
            return record
        }
    }

    @discardableResult
    public func toggleMasterGhostMode() async throws -> Bool {
        let updated = try await updateGlobalSettings { settings in
            settings.isMasterGhostEnabled.toggle()
        }
        return updated.isMasterGhostEnabled
    }

    public func fetchChatRule(for chatId: Int64) async throws -> StealthChatRuleRecord? {
        try await database.dbReader.read { db in
            try StealthChatRuleRecord.fetchOne(db, key: chatId)
        }
    }

    public func fetchAllChatRules() async throws -> [StealthChatRuleRecord] {
        try await database.dbReader.read { db in
            try StealthChatRuleRecord
                .order(StealthChatRuleRecord.Columns.updatedAt.desc)
                .fetchAll(db)
        }
    }

    public func setChatRule(_ rule: StealthChatRuleRecord) async throws {
        var mutable = rule
        mutable.updatedAt = Date()
        try await database.dbWriter.write { db in
            try mutable.save(db)
        }
    }

    public func removeChatRule(for chatId: Int64) async throws {
        try await database.dbWriter.write { db in
            _ = try StealthChatRuleRecord.deleteOne(db, key: chatId)
        }
    }

    public func effectivePolicy(for chatId: Int64?) async throws -> EffectiveStealthPolicy {
        try await database.dbReader.read { db in
            let global = try StealthSettingsRecord.fetchOne(db, key: StealthSettingsRecord.singletonId) ?? .default
            let rule: StealthChatRuleRecord?
            if let chatId {
                rule = try StealthChatRuleRecord.fetchOne(db, key: chatId)
            } else {
                rule = nil
            }
            return EffectiveStealthPolicy.resolve(global: global, chatRule: rule)
        }
    }

    public func observeGlobalSettings() -> AsyncThrowingStream<StealthSettingsRecord, Error> {
        let observation = ValueObservation.tracking { db in
            try StealthSettingsRecord.fetchOne(db, key: StealthSettingsRecord.singletonId) ?? .default
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

    public func observeAllChatRules() -> AsyncThrowingStream<[StealthChatRuleRecord], Error> {
        let observation = ValueObservation.tracking { db in
            try StealthChatRuleRecord
                .order(StealthChatRuleRecord.Columns.updatedAt.desc)
                .fetchAll(db)
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await rules in observation.values(in: database.dbReader) {
                        continuation.yield(rules)
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
