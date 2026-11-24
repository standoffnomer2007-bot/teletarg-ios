import Foundation
import LocalAuthentication

public enum VaultAccessState: Equatable, Sendable {
    case locked
    case unlockedReal
    case unlockedDecoy
}

public protocol BiometricVaultServiceProtocol: Sendable {
    func biometryDisplayName() -> String
    func canUseBiometrics() -> Bool
    func authenticateWithBiometrics(reason: String) async -> Bool
    func unlockWithPin(_ pin: String) -> VaultAccessState
}

public final class BiometricVaultService: BiometricVaultServiceProtocol, Sendable {
    private let keychain: any KeychainServiceProtocol

    public init(keychain: any KeychainServiceProtocol) {
        self.keychain = keychain
    }

    public func biometryDisplayName() -> String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "Биометрия"
        }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Биометрия"
        }
    }

    public func canUseBiometrics() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    public func authenticateWithBiometrics(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Ввести PIN"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch {
            return false
        }
    }

    public func unlockWithPin(_ pin: String) -> VaultAccessState {
        guard let result = try? keychain.verifyPin(pin) else {
            return .locked
        }
        switch result {
        case .realUnlocked: return .unlockedReal
        case .decoyUnlocked: return .unlockedDecoy
        case .invalid: return .locked
        }
    }
}
