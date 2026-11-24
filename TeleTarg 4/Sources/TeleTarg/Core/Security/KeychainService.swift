import CryptoKit
import Foundation
import Security

public enum KeychainKey: String, Sendable {
    case telegramApiId = "com.teletarg.telegram.api_id"
    case telegramApiHash = "com.teletarg.telegram.api_hash"
    case realPinHash = "com.teletarg.security.real_pin_hash"
    case decoyPinHash = "com.teletarg.security.decoy_pin_hash"
    case pinSalt = "com.teletarg.security.pin_salt"
}

public enum KeychainError: Error, LocalizedError, Sendable {
    case encodingFailed
    case unexpectedStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Не удалось закодировать данные для Keychain."
        case .unexpectedStatus(let status):
            return "Ошибка Keychain (код \(status))."
        }
    }
}

public protocol KeychainServiceProtocol: Sendable {
    func setString(_ value: String, for key: KeychainKey) throws
    func getString(for key: KeychainKey) throws -> String?
    func delete(for key: KeychainKey) throws
    func saveRealPin(_ pin: String) throws
    func saveDecoyPin(_ pin: String) throws
    func verifyPin(_ pin: String) throws -> PinVerificationResult
    func hasConfiguredPin() -> Bool
}

public enum PinVerificationResult: Equatable, Sendable {
    case realUnlocked
    case decoyUnlocked
    case invalid
}

public final class KeychainService: KeychainServiceProtocol, Sendable {
    private let serviceName: String

    public init(serviceName: String = "com.teletarg.ios.keychain") {
        self.serviceName = serviceName
    }

    public func setString(_ value: String, for key: KeychainKey) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try delete(for: key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func getString(for key: KeychainKey) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.unexpectedStatus(status)
        }
        return String(data: data, encoding: .utf8)
    }

    public func delete(for key: KeychainKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func saveRealPin(_ pin: String) throws {
        let salt = try ensurePinSalt()
        try setString(hashPin(pin, salt: salt), for: .realPinHash)
    }

    public func saveDecoyPin(_ pin: String) throws {
        let salt = try ensurePinSalt()
        try setString(hashPin(pin, salt: salt), for: .decoyPinHash)
    }

    public func verifyPin(_ pin: String) throws -> PinVerificationResult {
        guard let salt = try getString(for: .pinSalt) else { return .invalid }
        let candidate = hashPin(pin, salt: salt)
        if let real = try getString(for: .realPinHash), real == candidate {
            return .realUnlocked
        }
        if let decoy = try getString(for: .decoyPinHash), decoy == candidate {
            return .decoyUnlocked
        }
        return .invalid
    }

    public func hasConfiguredPin() -> Bool {
        (try? getString(for: .realPinHash)) != nil
    }

    private func ensurePinSalt() throws -> String {
        if let existing = try getString(for: .pinSalt) {
            return existing
        }
        let randomSalt = UUID().uuidString + UUID().uuidString
        try setString(randomSalt, for: .pinSalt)
        return randomSalt
    }

    private func hashPin(_ pin: String, salt: String) -> String {
        let digest = SHA256.hash(data: Data("\(salt)::\(pin)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
