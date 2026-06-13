import Foundation
import Security
import LocalAuthentication

enum KeychainError: Error, LocalizedError {
    case accessControl
    case status(OSStatus)
    var errorDescription: String? {
        switch self {
        case .accessControl: return "Could not create access control"
        case .status(let s):
            if s == errSecItemNotFound {
                return "This key's private material isn't in the Keychain — it may be from a previous build. Delete the key in Keys and re-import it."
            }
            let msg = SecCopyErrorMessageString(s, nil) as String? ?? "OSStatus \(s)"
            return "Keychain error: \(msg)"
        }
    }
}

/// Thin Keychain wrapper for storing key material. Imported secrets are stored
/// with a biometric (Touch ID) access-control gate; Secure Enclave key blobs are
/// already chip-bound, so they don't need a separate biometric gate to read.
enum Keychain {
    static let service = "dev.pulsevm.wallet.keys"

    static func save(account: String, data: Data, biometric: Bool) throws {
        delete(account: account) // overwrite semantics
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        if biometric {
            var err: Unmanaged<CFError>?
            guard let access = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                [.biometryCurrentSet], &err) else {
                throw KeychainError.accessControl
            }
            query[kSecAttrAccessControl as String] = access
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    /// Read an item; if it was stored biometric-gated this prompts Touch ID.
    static func load(account: String, reason: String) throws -> Data {
        let ctx = LAContext()
        ctx.localizedReason = reason
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: ctx,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else {
            throw KeychainError.status(status)
        }
        return data
    }

    /// Check an item exists WITHOUT prompting Touch ID (for health checks).
    /// errSecInteractionNotAllowed means it's there but biometric-gated → present.
    static func exists(account: String) -> Bool {
        let ctx = LAContext()
        ctx.interactionNotAllowed = true   // never prompt during a health check
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecUseAuthenticationContext as String: ctx,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}
