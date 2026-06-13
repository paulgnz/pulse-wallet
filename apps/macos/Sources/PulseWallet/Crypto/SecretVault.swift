import Foundation
import CryptoKit
import LocalAuthentication

enum VaultError: Error, LocalizedError {
    case io(String)
    case notFound
    var errorDescription: String? {
        switch self {
        case .io(let m): return m
        case .notFound: return "Key material not found — re-import this key."
        }
    }
}

/// File-based key storage that never touches the login keychain (so there is no
/// "enter your keychain password" ACL prompt). Two tiers:
///  • Enclave signing-key blobs are stored as-is — they're already bound to this
///    Mac's Secure Enclave and useless elsewhere.
///  • Imported raw private keys are **wrapped** with a Secure Enclave key-agreement
///    key (ECIES-style): encrypting uses the SE public key (no prompt); decrypting
///    runs the SE private key, which is biometric-gated → one Touch ID, no keychain.
enum SecretVault {
    private static let dir: URL = {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? FileManager.default.homeDirectoryForCurrentUser
        let d = base.appendingPathComponent("PulseVM/keys", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private static func url(_ id: String) -> URL { dir.appendingPathComponent(id).appendingPathExtension("bin") }
    private static let wrapURL = dir.appendingPathComponent("_wrap").appendingPathExtension("bin")
    private static let salt = Data("dev.pulsevm.wallet.kdf".utf8)

    // MARK: Plain blobs (Enclave dataRepresentation — device-bound, safe at rest)

    static func saveBlob(_ id: String, _ data: Data) throws {
        do { try data.write(to: url(id), options: .atomic) } catch { throw VaultError.io(error.localizedDescription) }
    }
    static func loadBlob(_ id: String) throws -> Data {
        guard let d = try? Data(contentsOf: url(id)) else { throw VaultError.notFound }
        return d
    }
    static func exists(_ id: String) -> Bool { FileManager.default.fileExists(atPath: url(id).path) }
    static func delete(_ id: String) { try? FileManager.default.removeItem(at: url(id)) }

    // MARK: Wrapped secrets (imported raw private keys)

    /// Encrypt `raw` to the Secure Enclave wrapping key (no Touch ID — uses pubkey).
    static func saveSecret(_ id: String, _ raw: Data) throws {
        let wrapPub = try wrappingPublicKey()
        let eph = P256.KeyAgreement.PrivateKey()
        let shared = try eph.sharedSecretFromKeyAgreement(with: wrapPub)
        let sym = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt,
                                                 sharedInfo: Data(), outputByteCount: 32)
        let sealed = try AES.GCM.seal(raw, using: sym)
        var blob = Data()
        blob.append(eph.publicKey.x963Representation)        // 65 bytes
        blob.append(sealed.combined!)                        // nonce+ct+tag
        try saveBlob(id, blob)
    }

    /// Decrypt an imported secret — runs the Enclave key, prompting Touch ID once.
    static func loadSecret(_ id: String, reason: String) throws -> Data {
        let blob = try loadBlob(id)
        guard blob.count > 65 else { throw VaultError.io("corrupt key blob") }
        let ephPub = try P256.KeyAgreement.PublicKey(x963Representation: blob.prefix(65))
        let sealed = try AES.GCM.SealedBox(combined: blob.dropFirst(65))
        let ctx = LAContext()
        ctx.localizedReason = reason
        let wrapData = try loadBlob("_wrap")
        let wrap = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: wrapData,
                                                                  authenticationContext: ctx)
        let shared = try wrap.sharedSecretFromKeyAgreement(with: ephPub)   // ← Touch ID here
        let sym = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt,
                                                 sharedInfo: Data(), outputByteCount: 32)
        return try AES.GCM.open(sealed, using: sym)
    }

    /// The Secure Enclave wrapping key's public key (creating it on first use).
    private static func wrappingPublicKey() throws -> P256.KeyAgreement.PublicKey {
        if let data = try? Data(contentsOf: wrapURL) {
            // Reconstructing + reading the public key does NOT prompt.
            return try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: data).publicKey
        }
        var err: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet], &err) else {
            throw VaultError.io("could not create access control")
        }
        let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access)
        try key.dataRepresentation.write(to: wrapURL, options: .atomic)
        return key.publicKey
    }
}
