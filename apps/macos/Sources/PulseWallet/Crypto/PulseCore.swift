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

    func encodePvtR1(_ raw: Data) -> String         // raw32 -> "PVT_R1_…"

    // K1 (secp256k1) — for existing Antelope accounts.
    func decodePvtK1(_ wif: String) -> Data?        // "PVT_K1_…" or legacy WIF
    func encodePvtK1(_ raw: Data) -> String         // raw32 -> "PVT_K1_…"
    func generateK1() -> Data                       // fresh random K1 private key (32B)
    func pubK1(privateKey: Data) -> Data?           // raw32 -> 33B compressed
    func encodePubK1(compressedPublicKey: Data) -> String
    func signK1(privateKey: Data, digest: Data) throws -> String

    /// Serialize a transfer and return its signing material (hex strings).
    func buildTransfer(from: String, to: String, quantity: String, memo: String,
                       contract: String, actor: String, permission: String,
                       chainId: String, refBlockNum: UInt16, refBlockPrefix: UInt32,
                       expiration: UInt32) throws -> BuiltTx

    // pulse.msig
    func msigProposeTransfer(contract: String, proposer: String, proposal: String,
                             requested: String, from: String, to: String, quantity: String,
                             memo: String, tokenContract: String, innerExpiration: UInt32,
                             chainId: String, refBlockNum: UInt16, refBlockPrefix: UInt32,
                             expiration: UInt32) throws -> BuiltTx
    func msigApprove(contract: String, proposer: String, proposal: String,
                     levelActor: String, levelPerm: String, authActor: String, authPerm: String,
                     chainId: String, refBlockNum: UInt16, refBlockPrefix: UInt32,
                     expiration: UInt32) throws -> BuiltTx
    func msigExec(contract: String, proposer: String, proposal: String, executer: String,
                  chainId: String, refBlockNum: UInt16, refBlockPrefix: UInt32,
                  expiration: UInt32) throws -> BuiltTx

    // Resources (pulse system contract)
    func buildStake(contract: String, from: String, receiver: String, netQty: String, cpuQty: String,
                    transfer: Bool, chainId: String, refBlockNum: UInt16, refBlockPrefix: UInt32,
                    expiration: UInt32) throws -> BuiltTx
    func buildUnstake(contract: String, from: String, receiver: String, netQty: String, cpuQty: String,
                      chainId: String, refBlockNum: UInt16, refBlockPrefix: UInt32,
                      expiration: UInt32) throws -> BuiltTx
    func buildRefund(contract: String, owner: String, chainId: String, refBlockNum: UInt16,
                     refBlockPrefix: UInt32, expiration: UInt32) throws -> BuiltTx

    /// Preimage + digest for an externally-supplied packed tx (dapp transport).
    func signingMaterial(packedTrx: String, chainId: String) throws -> (preimage: String, digest: String)

    /// Decode a packed tx so the user can see what they're signing (nil if undecodable).
    func decodeTransaction(packedTrx: String) -> DecodedTx?

    /// updateauth — set an account permission to threshold-of weighted keys.
    /// `keys` is "PUB_..@weight;PUB_..@weight".
    func buildUpdateAuth(systemContract: String, account: String, permission: String,
                         parent: String, threshold: UInt32, keys: String,
                         authActor: String, authPerm: String, chainId: String,
                         refBlockNum: UInt16, refBlockPrefix: UInt32, expiration: UInt32) throws -> BuiltTx

    /// updateauth with a full authority: keys "PUB@w;…", accounts "actor@perm@w;…", waits "sec@w;…".
    func buildUpdateAuthFull(systemContract: String, account: String, permission: String,
                             parent: String, threshold: UInt32,
                             keys: String, accounts: String, waits: String,
                             authActor: String, authPerm: String, chainId: String,
                             refBlockNum: UInt16, refBlockPrefix: UInt32, expiration: UInt32) throws -> BuiltTx

    /// linkauth: bind `account`'s `requirement` permission to `code`::`type` (empty type = all actions).
    func buildLinkAuth(systemContract: String, account: String, code: String, type: String,
                       requirement: String, authActor: String, authPerm: String, chainId: String,
                       refBlockNum: UInt16, refBlockPrefix: UInt32, expiration: UInt32) throws -> BuiltTx

    /// unlinkauth: remove the link binding `code`::`type` for `account`.
    func buildUnlinkAuth(systemContract: String, account: String, code: String, type: String,
                         authActor: String, authPerm: String, chainId: String,
                         refBlockNum: UInt16, refBlockPrefix: UInt32, expiration: UInt32) throws -> BuiltTx

    /// deleteauth: remove `permission` from `account`.
    func buildDeleteAuth(systemContract: String, account: String, permission: String,
                         authActor: String, authPerm: String, chainId: String,
                         refBlockNum: UInt16, refBlockPrefix: UInt32, expiration: UInt32) throws -> BuiltTx
}

/// Serialized transaction + its signing material (all hex).
struct BuiltTx: Sendable {
    let packed: String
    let preimage: String
    let digest: String
}

/// A decoded transaction — what the user is actually about to sign.
struct DecodedTx: Decodable, Sendable {
    let expiration: UInt32
    let refBlockNum: UInt16
    let actions: [Action]

    struct Action: Decodable, Sendable, Identifiable {
        let account: String
        let name: String
        let authorization: [Auth]
        let dataHex: String
        let transfer: Transfer?
        var id: String { account + "::" + name + dataHex }

        struct Auth: Decodable, Sendable { let actor: String; let permission: String }
        struct Transfer: Decodable, Sendable {
            let from: String; let to: String; let quantity: String; let memo: String
        }
    }
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
    func encodePvtR1(_ raw: Data) -> String { "" }
    func decodePvtK1(_ wif: String) -> Data? { nil }
    func encodePvtK1(_ raw: Data) -> String { "" }
    func generateK1() -> Data { Data() }
    func pubK1(privateKey: Data) -> Data? { nil }
    func encodePubK1(compressedPublicKey: Data) -> String { "" }
    func signK1(privateKey: Data, digest: Data) throws -> String {
        throw PulseCoreError.notImplemented("signK1")
    }
    func buildTransfer(from: String, to: String, quantity: String, memo: String,
                       contract: String, actor: String, permission: String,
                       chainId: String, refBlockNum: UInt16, refBlockPrefix: UInt32,
                       expiration: UInt32) throws -> BuiltTx {
        throw PulseCoreError.notImplemented("buildTransfer")
    }
    func msigProposeTransfer(contract: String, proposer: String, proposal: String,
                             requested: String, from: String, to: String, quantity: String,
                             memo: String, tokenContract: String, innerExpiration: UInt32,
                             chainId: String, refBlockNum: UInt16, refBlockPrefix: UInt32,
                             expiration: UInt32) throws -> BuiltTx {
        throw PulseCoreError.notImplemented("msigProposeTransfer")
    }
    func msigApprove(contract: String, proposer: String, proposal: String,
                     levelActor: String, levelPerm: String, authActor: String, authPerm: String,
                     chainId: String, refBlockNum: UInt16, refBlockPrefix: UInt32,
                     expiration: UInt32) throws -> BuiltTx {
        throw PulseCoreError.notImplemented("msigApprove")
    }
    func msigExec(contract: String, proposer: String, proposal: String, executer: String,
                  chainId: String, refBlockNum: UInt16, refBlockPrefix: UInt32,
                  expiration: UInt32) throws -> BuiltTx {
        throw PulseCoreError.notImplemented("msigExec")
    }
    func buildStake(contract: String, from: String, receiver: String, netQty: String, cpuQty: String,
                    transfer: Bool, chainId: String, refBlockNum: UInt16, refBlockPrefix: UInt32,
                    expiration: UInt32) throws -> BuiltTx { throw PulseCoreError.notImplemented("buildStake") }
    func buildUnstake(contract: String, from: String, receiver: String, netQty: String, cpuQty: String,
                      chainId: String, refBlockNum: UInt16, refBlockPrefix: UInt32,
                      expiration: UInt32) throws -> BuiltTx { throw PulseCoreError.notImplemented("buildUnstake") }
    func buildRefund(contract: String, owner: String, chainId: String, refBlockNum: UInt16,
                     refBlockPrefix: UInt32, expiration: UInt32) throws -> BuiltTx { throw PulseCoreError.notImplemented("buildRefund") }
    func signingMaterial(packedTrx: String, chainId: String) throws -> (preimage: String, digest: String) {
        throw PulseCoreError.notImplemented("signingMaterial")
    }
    func decodeTransaction(packedTrx: String) -> DecodedTx? { nil }
    func buildUpdateAuth(systemContract: String, account: String, permission: String,
                         parent: String, threshold: UInt32, keys: String,
                         authActor: String, authPerm: String, chainId: String,
                         refBlockNum: UInt16, refBlockPrefix: UInt32, expiration: UInt32) throws -> BuiltTx {
        throw PulseCoreError.notImplemented("buildUpdateAuth")
    }
    func buildUpdateAuthFull(systemContract: String, account: String, permission: String,
                             parent: String, threshold: UInt32, keys: String, accounts: String, waits: String,
                             authActor: String, authPerm: String, chainId: String,
                             refBlockNum: UInt16, refBlockPrefix: UInt32, expiration: UInt32) throws -> BuiltTx {
        throw PulseCoreError.notImplemented("buildUpdateAuthFull")
    }
    func buildLinkAuth(systemContract: String, account: String, code: String, type: String,
                       requirement: String, authActor: String, authPerm: String, chainId: String,
                       refBlockNum: UInt16, refBlockPrefix: UInt32, expiration: UInt32) throws -> BuiltTx {
        throw PulseCoreError.notImplemented("buildLinkAuth")
    }
    func buildUnlinkAuth(systemContract: String, account: String, code: String, type: String,
                         authActor: String, authPerm: String, chainId: String,
                         refBlockNum: UInt16, refBlockPrefix: UInt32, expiration: UInt32) throws -> BuiltTx {
        throw PulseCoreError.notImplemented("buildUnlinkAuth")
    }
    func buildDeleteAuth(systemContract: String, account: String, permission: String,
                         authActor: String, authPerm: String, chainId: String,
                         refBlockNum: UInt16, refBlockPrefix: UInt32, expiration: UInt32) throws -> BuiltTx {
        throw PulseCoreError.notImplemented("buildDeleteAuth")
    }
}
