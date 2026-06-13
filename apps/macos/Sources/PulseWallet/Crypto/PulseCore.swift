import Foundation

/// Swift-facing surface of the shared Rust core (`pulse-wallet-core`).
///
/// The Rust core owns all chain logic that must match the network exactly:
///   • recovery-id derivation + SIG_R1 assembly (validated vs pulsevm-js)
///   • PUB_R1 encoding
///   • transaction serialization + the signing digest
///   • RPC / REST client
///
/// It is exposed to Swift via a uniffi binding. Until that binding is generated,
/// this protocol lets the UI compile and run against `PulseCoreStub`. Swapping in
/// the generated `PulseCoreFFI` is a one-line change in `AppModel`.
protocol PulseCore {
    /// 33-byte compressed SEC1 pubkey  →  "PUB_R1_…"
    func encodePubR1(compressedPublicKey: Data) -> String

    /// raw r‖s (64B) + 32B digest + 33B compressed pubkey  →  "SIG_R1_…"
    /// Derives the recovery id by recover-and-match; normalizes to low-s.
    func assembleSigR1(rs: Data, digest: Data, compressedPublicKey: Data) throws -> String

    /// Decode a "PVT_R1_…" private key to its raw 32 bytes (nil if invalid).
    func decodePvtR1(_ wif: String) -> Data?

    // K1 (secp256k1) — for existing Antelope accounts.
    func decodePvtK1(_ wif: String) -> Data?        // "PVT_K1_…" or legacy WIF
    func pubK1(privateKey: Data) -> Data?           // raw32 -> 33B compressed
    func encodePubK1(compressedPublicKey: Data) -> String
    func signK1(privateKey: Data, digest: Data) throws -> String

    /// Serialize a transfer and return its signing material (hex strings).
    func buildTransfer(from: String, to: String, quantity: String, memo: String,
                       contract: String, actor: String, permission: String,
                       chainId: String, refBlockNum: UInt16, refBlockPrefix: UInt32,
                       expiration: UInt32) throws -> (packed: String, preimage: String, digest: String)
}

enum PulseCoreError: Error, LocalizedError {
    case notImplemented(String)
    case signing(String)
    case badInput(String)

    var errorDescription: String? {
        switch self {
        case .notImplemented(let m): return "Not implemented: \(m)"
        case .signing(let m):        return "Signing failed: \(m)"
        case .badInput(let m):       return "Invalid input: \(m)"
        }
    }
}

/// Stand-in until the uniffi binding ships. Returns clearly-fake values so the
/// UI is exercisable without claiming to be real.
struct PulseCoreStub: PulseCore {
    func encodePubR1(compressedPublicKey: Data) -> String {
        "PUB_R1_stub\(compressedPublicKey.prefix(3).map { String(format: "%02x", $0) }.joined())"
    }
    func assembleSigR1(rs: Data, digest: Data, compressedPublicKey: Data) throws -> String {
        throw PulseCoreError.notImplemented("assembleSigR1 — wire pulse-wallet-core via uniffi")
    }
    func decodePvtR1(_ wif: String) -> Data? { nil }
    func decodePvtK1(_ wif: String) -> Data? { nil }
    func pubK1(privateKey: Data) -> Data? { nil }
    func encodePubK1(compressedPublicKey: Data) -> String { "" }
    func signK1(privateKey: Data, digest: Data) throws -> String {
        throw PulseCoreError.notImplemented("signK1")
    }
    func buildTransfer(from: String, to: String, quantity: String, memo: String,
                       contract: String, actor: String, permission: String,
                       chainId: String, refBlockNum: UInt16, refBlockPrefix: UInt32,
                       expiration: UInt32) throws -> (packed: String, preimage: String, digest: String) {
        throw PulseCoreError.notImplemented("buildTransfer")
    }
}
