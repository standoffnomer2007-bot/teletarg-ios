import Foundation
import GRDB

public protocol ProfileOverrideRepositoryProtocol: Sendable {
    func fetchOverride(for userId: Int64) async throws -> ProfileOverrideRecord?
    func fetchOverrides(for userIds: [Int64]) async throws -> [Int64: ProfileOverrideRecord]
    func saveOverride(_ record: ProfileOverrideRecord) async throws
    func saveAvatarMedia(for userId: Int64, sourceURL: URL, isVideo: Bool) async throws -> String
    func resetField(_ field: ProfileOverrideField, for userId: Int64) async throws
    func resetProfile(for userId: Int64) async throws
    func mergeProfile(remote: RemoteUserProfile) async throws -> EffectiveUserProfile
    func mergeProfiles(remotes: [RemoteUserProfile]) async throws -> [EffectiveUserProfile]
    func observeOverride(for userId: Int64) -> AsyncThrowingStream<ProfileOverrideRecord?, Error>
    func observeAllOverrides() -> AsyncThrowingStream<[Int64: ProfileOverrideRecord], Error>
}

public final class ProfileOverrideRepository: ProfileOverrideRepositoryProtocol, Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func fetchOverride(for userId: Int64) async throws -> ProfileOverrideRecord? {
        try await database.dbReader.read { db in
            try ProfileOverrideRecord.fetchOne(db, key: userId)
        }
    }

    public func fetchOverrides(for userIds: [Int64]) async throws -> [Int64: ProfileOverrideRecord] {
        guard !userIds.isEmpty else { return [:] }
        return try await database.dbReader.read { db in
            let records = try ProfileOverrideRecord
                .filter(userIds.contains(ProfileOverrideRecord.Columns.userId))
                .fetchAll(db)
            return Dictionary(uniqueKeysWithValues: records.map { ($0.userId, $0) })
        }
    }

    public func saveOverride(_ record: ProfileOverrideRecord) async throws {
        var mutable = record
        mutable.updatedAt = Date()
        if mutable.isEmpty {
            try await resetProfile(for: mutable.userId)
            return
        }
        try await database.dbWriter.write { db in
            try mutable.save(db)
        }
    }

    public func saveAvatarMedia(for userId: Int64, sourceURL: URL, isVideo: Bool) async throws -> String {
        let fm = FileManager.default
        let ext = sourceURL.pathExtension.isEmpty ? (isVideo ? "mp4" : "jpg") : sourceURL.pathExtension
        let fileName = "avatar_\(userId)_\(Int(Date().timeIntervalSince1970)).\(ext)"
        let destinationURL = database.avatarOverridesDirectory.appendingPathComponent(fileName)

        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }
        try fm.copyItem(at: sourceURL, to: destinationURL)
        try? fm.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: destinationURL.path
        )

        try await database.dbWriter.write { db in
            var record = try ProfileOverrideRecord.fetchOne(db, key: userId) ?? ProfileOverrideRecord(userId: userId)
            if let oldPath = record.avatarLocalPath, oldPath != destinationURL.path {
                try? fm.removeItem(atPath: oldPath)
            }
            record.avatarLocalPath = destinationURL.path
            record.avatarIsVideo = isVideo
            record.updatedAt = Date()
            try record.save(db)
        }

        return destinationURL.path
    }

    public func resetField(_ field: ProfileOverrideField, for userId: Int64) async throws {
        let fm = FileManager.default
        try await database.dbWriter.write { db in
            guard var record = try ProfileOverrideRecord.fetchOne(db, key: userId) else { return }
            if field == .avatarLocalPath, let path = record.avatarLocalPath {
                try? fm.removeItem(atPath: path)
            }
            record.reset(field: field)
            if record.isEmpty {
                try record.delete(db)
            } else {
                try record.save(db)
            }
        }
    }

    public func resetProfile(for userId: Int64) async throws {
        let fm = FileManager.default
        try await database.dbWriter.write { db in
            if let existing = try ProfileOverrideRecord.fetchOne(db, key: userId),
               let avatarPath = existing.avatarLocalPath {
                try? fm.removeItem(atPath: avatarPath)
            }
            _ = try ProfileOverrideRecord.deleteOne(db, key: userId)
        }
    }

    public func mergeProfile(remote: RemoteUserProfile) async throws -> EffectiveUserProfile {
        let overrideRecord = try await fetchOverride(for: remote.userId)
        return EffectiveUserProfile.merge(remote: remote, override: overrideRecord)
    }

    public func mergeProfiles(remotes: [RemoteUserProfile]) async throws -> [EffectiveUserProfile] {
        let ids = remotes.map(\.userId)
        let overrides = try await fetchOverrides(for: ids)
        return remotes.map { remote in
            EffectiveUserProfile.merge(remote: remote, override: overrides[remote.userId])
        }
    }

    public func observeOverride(for userId: Int64) -> AsyncThrowingStream<ProfileOverrideRecord?, Error> {
        let observation = ValueObservation.tracking { db in
            try ProfileOverrideRecord.fetchOne(db, key: userId)
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await value in observation.values(in: database.dbReader) {
                        continuation.yield(value)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func observeAllOverrides() -> AsyncThrowingStream<[Int64: ProfileOverrideRecord], Error> {
        let observation = ValueObservation.tracking { db -> [Int64: ProfileOverrideRecord] in
            let all = try ProfileOverrideRecord.fetchAll(db)
            return Dictionary(uniqueKeysWithValues: all.map { ($0.userId, $0) })
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await value in observation.values(in: database.dbReader) {
                        continuation.yield(value)
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
