import CryptoKit
import Foundation
import GRDB

public struct TeleTargBackupPayload: Codable, Sendable {
    public let schemaVersion: Int
    public let exportedAt: Date
    public let appSettings: AppSettingsRecord
    public let stealthSettings: StealthSettingsRecord
    public let stealthChatRules: [StealthChatRuleRecord]
    public let profileOverrides: [ProfileOverrideRecord]
    public let hiddenChats: [HiddenChatRecord]
    public let discordServerMappings: [DiscordServerMappingRecord]
    public let deletedMessages: [CachedMessageRecord]
    public let editRevisions: [MessageEditRevisionRecord]
}

public enum EncryptedBackupError: Error, LocalizedError, Sendable {
    case emptyPassphrase
    case invalidEnvelope
    case decryptionFailed

    public var errorDescription: String? {
        switch self {
        case .emptyPassphrase:
            return "Пароль для шифрования бэкапа не может быть пустым."
        case .invalidEnvelope:
            return "Файл бэкапа повреждён или имеет неподдерживаемый формат."
        case .decryptionFailed:
            return "Не удалось расшифровать бэкап. Проверьте пароль."
        }
    }
}

private struct EncryptedBackupEnvelope: Codable {
    let magic: String
    let version: Int
    let saltBase64: String
    let sealedBoxBase64: String
}

public protocol EncryptedBackupRepositoryProtocol: Sendable {
    func exportEncryptedBackup(passphrase: String) async throws -> Data
    func importEncryptedBackup(_ data: Data, passphrase: String, replaceExisting: Bool) async throws
}

public final class EncryptedBackupRepository: EncryptedBackupRepositoryProtocol, Sendable {
    private static let magicHeader = "TTBKP_AESGCM_V1"
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func exportEncryptedBackup(passphrase: String) async throws -> Data {
        guard !passphrase.isEmpty else { throw EncryptedBackupError.emptyPassphrase }

        let payload: TeleTargBackupPayload = try await database.dbReader.read { db in
            let appSettings = try AppSettingsRecord.fetchOne(db, key: AppSettingsRecord.singletonId) ?? .default
            let stealthSettings = try StealthSettingsRecord.fetchOne(db, key: StealthSettingsRecord.singletonId) ?? .default
            let stealthRules = try StealthChatRuleRecord.fetchAll(db)
            let overrides = try ProfileOverrideRecord.fetchAll(db)
            let hiddenChats = try HiddenChatRecord.fetchAll(db)
            let discordMappings = try DiscordServerMappingRecord.fetchAll(db)
            let deletedMessages = try CachedMessageRecord
                .filter(CachedMessageRecord.Columns.isDeletedLocally == true || CachedMessageRecord.Columns.editCount > 0)
                .fetchAll(db)
            let revisions = try MessageEditRevisionRecord.fetchAll(db)

            return TeleTargBackupPayload(
                schemaVersion: 1,
                exportedAt: Date(),
                appSettings: appSettings,
                stealthSettings: stealthSettings,
                stealthChatRules: stealthRules,
                profileOverrides: overrides,
                hiddenChats: hiddenChats,
                discordServerMappings: discordMappings,
                deletedMessages: deletedMessages,
                editRevisions: revisions
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let plaintext = try encoder.encode(payload)

        var saltBytes = [UInt8](repeating: 0, count: 32)
        for index in saltBytes.indices {
            saltBytes[index] = UInt8.random(in: 0...255)
        }
        let salt = Data(saltBytes)
        let key = deriveKey(passphrase: passphrase, salt: salt)
        let sealedBox = try AES.GCM.seal(plaintext, using: key)

        guard let combined = sealedBox.combined else {
            throw EncryptedBackupError.invalidEnvelope
        }

        let envelope = EncryptedBackupEnvelope(
            magic: Self.magicHeader,
            version: 1,
            saltBase64: salt.base64EncodedString(),
            sealedBoxBase64: combined.base64EncodedString()
        )
        return try encoder.encode(envelope)
    }

    public func importEncryptedBackup(
        _ data: Data,
        passphrase: String,
        replaceExisting: Bool = true
    ) async throws {
        guard !passphrase.isEmpty else { throw EncryptedBackupError.emptyPassphrase }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let envelope = try? decoder.decode(EncryptedBackupEnvelope.self, from: data),
              envelope.magic == Self.magicHeader,
              let salt = Data(base64Encoded: envelope.saltBase64),
              let combined = Data(base64Encoded: envelope.sealedBoxBase64) else {
            throw EncryptedBackupError.invalidEnvelope
        }

        let key = deriveKey(passphrase: passphrase, salt: salt)
        let plaintext: Data
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            plaintext = try AES.GCM.open(box, using: key)
        } catch {
            throw EncryptedBackupError.decryptionFailed
        }

        let payload = try decoder.decode(TeleTargBackupPayload.self, from: plaintext)

        try await database.dbWriter.write { db in
            if replaceExisting {
                try ProfileOverrideRecord.deleteAll(db)
                try StealthChatRuleRecord.deleteAll(db)
                try HiddenChatRecord.deleteAll(db)
                try DiscordServerMappingRecord.deleteAll(db)
            }

            try payload.appSettings.save(db)
            try payload.stealthSettings.save(db)

            for rule in payload.stealthChatRules {
                try rule.save(db)
            }
            for overrideRecord in payload.profileOverrides {
                try overrideRecord.save(db)
            }
            for hidden in payload.hiddenChats {
                try hidden.save(db)
            }
            for mapping in payload.discordServerMappings {
                try mapping.save(db)
            }
            for message in payload.deletedMessages {
                try message.save(db)
            }
            for var revision in payload.editRevisions {
                revision.id = nil
                try revision.insert(db)
            }
        }
    }

    private func deriveKey(passphrase: String, salt: Data) -> SymmetricKey {
        let inputKey = SymmetricKey(data: Data(passphrase.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: Data("TeleTarg.EncryptedBackup.v1".utf8),
            outputByteCount: 32
        )
    }
}
