import Foundation
import CryptoKit
import LocalAuthentication

/// Secure Enclave key management for PulseVM (R1 / secp256r1 / P-256).
///
/// The Enclave produces a NON-recoverable ECDSA signature (raw r‖s). PulseVM
/// verifies by *recovering* the public key, so the recovery id must be derived
/// off-chip — that happens in the Rust core (`pulse-wallet-core::assemble_sig_r1`,
/// validated byte-for-byte against pulsevm-js). This type only owns the chip:
/// keygen, public-key export, and producing raw r‖s under biometric gate.
enum EnclaveSigner {

    struct KeyHandle {
        let key: SecureEnclave.P256.Signing.PrivateKey
        /// 33-byte compressed SEC1 public key → fed to core.encode_pub_r1().
        var compressedPublicKey: Data { key.publicKey.compressedRepresentation }
    }

    enum SignerError: Error { case enclaveUnavailable, accessControl(String) }

    /// True on Macs with the Secure Enclave (Apple silicon / T2).
    static var isAvailable: Bool { SecureEnclave.isAvailable }

    /// Create a new biometric-gated key in the Secure Enclave.
    /// `.biometryCurrentSet` invalidates the key if enrolled biometrics change.
    static func createKey() throws -> KeyHandle {
        guard SecureEnclave.isAvailable else { throw SignerError.enclaveUnavailable }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet],
            &error)
        else {
            throw SignerError.accessControl(String(describing: error?.takeRetainedValue()))
        }
        let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access)
        return KeyHandle(key: key)
    }

    /// Restore a key handle from its persisted (encrypted) data representation.
    static func load(from dataRepresentation: Data) throws -> KeyHandle {
        let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: dataRepresentation)
        return KeyHandle(key: key)
    }

    /// Persisted, per-account Enclave key. The `dataRepresentation` is an
    /// encrypted blob that only this Secure Enclave can use, so it is safe to
    /// store in UserDefaults; the private key never leaves the chip.
    static func handle(forAccount account: String) throws -> KeyHandle {
        let defaultsKey = "enclaveKey.\(account)"
        if let data = UserDefaults.standard.data(forKey: defaultsKey) {
            return try load(from: data)
        }
        let handle = try createKey()
        UserDefaults.standard.set(handle.key.dataRepresentation, forKey: defaultsKey)
        return handle
    }

    /// Sign the transaction PRE-IMAGE and return raw r‖s (64 bytes).
    ///
    /// IMPORTANT: CryptoKit's `signature(for:)` hashes the input with SHA-256
    /// internally. PulseVM's signing digest is `sha256(chain_id ‖ packed_trx ‖
    /// sha256(cfd))`. So we pass the **pre-image** (the bytes that hash to the
    /// digest) here — NOT the digest — to avoid double-hashing. The Rust core
    /// then derives the recid against that same digest.
    static func signPreImage(_ preImage: Data,
                             with handle: KeyHandle,
                             reason: String = "Sign PulseVM transaction") throws -> Data {
        let ctx = LAContext()
        ctx.localizedReason = reason
        let signature = try handle.key.signature(for: preImage)
        return signature.rawRepresentation   // 64 bytes: r(32) ‖ s(32)
    }

    /// Convenience: load/create the account's key and sign, off the main actor.
    /// Returns raw r‖s. The (non-Sendable) Enclave key never crosses an actor
    /// boundary — only the resulting `Data` does.
    static func sign(account: String, preImage: Data, reason: String) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let handle = try handle(forAccount: account)
            return try signPreImage(preImage, with: handle, reason: reason)
        }.value
    }
}
