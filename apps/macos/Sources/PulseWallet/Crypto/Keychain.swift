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

/// Thin Keychain wrapper. Items are stored in the standard (file) login keychain
/// — NOT the data-protection keychain — so no `keychain-access-groups` entitlement
/// / provisioning profile is required (Mac apps often have none). Touch ID is
/// enforced in our own code (see `Biometrics`) before reading a secret, so the
/// UX is the same without the entitlement dependency. Access is bound to the
/// app's code signature, so a stable signing Team keeps items readable across builds.
enum Keychain {
    static let service = "dev.pulsevm.wallet.keys"

    static func save(account: String, data: Data) throws {
        delete(account: account) // overwrite semantics
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    static func load(account: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else {
            throw KeychainError.status(status)
        }
        return data
    }

    /// Check an item exists (no prompt; plain items don't require auth).
    static func exists(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
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
