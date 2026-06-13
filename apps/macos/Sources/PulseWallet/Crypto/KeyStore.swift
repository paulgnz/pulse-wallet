import Foundation
import CryptoKit
import Observation

/// A managed wallet key. Private material lives in the Keychain / Secure Enclave;
/// only this metadata is persisted in defaults.
struct WalletKey: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case enclave, imported }
    enum Curve: String, Codable { case r1, k1 }
    let id: String                 // UUID, also the Keychain account name
    var label: String
    let kind: Kind
    var curve: Curve = .r1
    let pubCompressedHex: String   // 33-byte compressed key, hex
    var pubKey: String             // PUB_R1_… or PUB_K1_…
    let createdAt: Date

    var isHardwareBacked: Bool { kind == .enclave }
}

/// Stores, lists, imports, and deletes wallet keys.
@MainActor
@Observable
final class KeyStore {
    private let defaultsKey = "wallet.keys.v1"
    private let core: PulseCore = PulseCoreFFI()
    private(set) var keys: [WalletKey] = []
    var activeKeyID: String? {
        didSet { UserDefaults.standard.set(activeKeyID, forKey: "wallet.activeKeyID") }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let arr = try? JSONDecoder().decode([WalletKey].self, from: data) {
            keys = arr
        }
        activeKeyID = UserDefaults.standard.string(forKey: "wallet.activeKeyID")
    }

    var activeKey: WalletKey? { keys.first { $0.id == activeKeyID } }

    private func persist() {
        if let data = try? JSONEncoder().encode(keys) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    // MARK: Create / import

    /// Generate a new biometric-gated Secure Enclave key.
    @discardableResult
    func createEnclaveKey(label: String) throws -> WalletKey {
        let handle = try EnclaveSigner.createKey()
        let pub = handle.compressedPublicKey
        let id = UUID().uuidString
        try Keychain.save(account: id, data: handle.key.dataRepresentation, biometric: false)
        let key = WalletKey(id: id, label: label.isEmpty ? "Enclave key" : label,
                            kind: .enclave, curve: .r1, pubCompressedHex: pub.hexString,
                            pubKey: core.encodePubR1(compressedPublicKey: pub), createdAt: Date())
        keys.append(key)
        persist()
        if activeKeyID == nil { activeKeyID = id }
        return key
    }

    /// Import a private key. R1 ("PVT_R1_…"/hex) or K1 ("PVT_K1_…"/WIF).
    /// Stored in the Keychain behind Touch ID.
    @discardableResult
    func importKey(secret: String, label: String, curve: WalletKey.Curve) throws -> WalletKey {
        let raw = try rawSecret(from: secret, curve: curve)
        let pub: Data
        switch curve {
        case .r1:
            pub = try P256.Signing.PrivateKey(rawRepresentation: raw).publicKey.compressedRepresentation
        case .k1:
            guard let p = core.pubK1(privateKey: raw) else {
                throw PulseCoreError.badInput("invalid K1 private key")
            }
            pub = p
        }
        let hex = pub.hexString
        if let existing = keys.first(where: { $0.pubCompressedHex == hex }) {
            throw PulseCoreError.badInput("key already imported (\(existing.label))")
        }
        let pubStr = curve == .r1
            ? core.encodePubR1(compressedPublicKey: pub)
            : core.encodePubK1(compressedPublicKey: pub)
        let id = UUID().uuidString
        try Keychain.save(account: id, data: raw, biometric: true)
        let key = WalletKey(id: id, label: label.isEmpty ? "Imported key" : label,
                            kind: .imported, curve: curve, pubCompressedHex: hex,
                            pubKey: pubStr, createdAt: Date())
        keys.append(key)
        persist()
        if activeKeyID == nil { activeKeyID = id }
        return key
    }

    /// Remove a key from the store and Keychain. UI gates this with Touch ID +
    /// a typed "DELETE" confirmation.
    func delete(_ key: WalletKey) {
        Keychain.delete(account: key.id)
        keys.removeAll { $0.id == key.id }
        if activeKeyID == key.id { activeKeyID = keys.first?.id }
        persist()
    }

    func rename(_ key: WalletKey, to label: String) {
        guard let idx = keys.firstIndex(of: key) else { return }
        keys[idx].label = label
        persist()
    }

    private func rawSecret(from secret: String, curve: WalletKey.Curve) throws -> Data {
        let t = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("PVT_R1_") {
            guard let raw = core.decodePvtR1(t) else {
                throw PulseCoreError.badInput("invalid PVT_R1 key (bad checksum?)")
            }
            return raw
        }
        if t.hasPrefix("PVT_K1_") || t.first == "5" {  // PVT_K1 or legacy WIF
            guard let raw = core.decodePvtK1(t) else {
                throw PulseCoreError.badInput("invalid K1 key (bad checksum?)")
            }
            return raw
        }
        let hex = t.hasPrefix("0x") ? String(t.dropFirst(2)) : t
        guard hex.count == 64, let raw = Data(hexString: hex) else {
            throw PulseCoreError.badInput("expected a PVT_R1_…/PVT_K1_…/WIF key or 64-char hex")
        }
        return raw
    }

    /// Detect the likely curve from a pasted secret's prefix.
    static func detectCurve(_ secret: String) -> WalletKey.Curve {
        let t = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("PVT_K1_") || t.first == "5" { return .k1 }
        return .r1
    }
}
