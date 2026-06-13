import Foundation
import CryptoKit

// Spike: can a Secure Enclave P-256 (= secp256r1 = PulseVM R1) key produce a
// signature PulseVM accepts? PulseVM RECOVERS the pubkey from the signature, so
// the (non-recoverable) Enclave ECDSA must be wrapped with a derived recovery id.
// Steps 1-3 below work today; steps 4-5 are the porting work (see TODOs).
//
// IMPORTANT: PulseVM/Antelope signs sha256(chain_id ‖ packed_trx ‖ sha256(cfd)).
// CryptoKit's `signature(for: data)` hashes with SHA256 internally, so we sign the
// PRE-IMAGE (chain_id ‖ packed_trx ‖ sha256(cfd)) — NOT the already-hashed digest —
// to avoid double-hashing. The recovery digest is then SHA256(preimage).

func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }

guard SecureEnclave.isAvailable else {
  print("❌ Secure Enclave not available on this machine."); exit(1)
}

// --- 1. Generate a key IN the Secure Enclave (biometric-gated) ---------------
let access = SecAccessControlCreateWithFlags(
  nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
  [.privateKeyUsage, .biometryCurrentSet], nil)!
let priv = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access)
let pub = priv.publicKey
print("✓ Enclave key created")
print("  pubkey (x963, 65B): \(hex(pub.x963Representation))")
// TODO(step 1b): compress x963 (0x02/0x03 ‖ x) and encode as PUB_R1_… (port from pulsevm-js)

// --- 2. Build the Antelope signing PRE-IMAGE (placeholder) ------------------
// TODO(step 2): replace with chain_id ‖ packed_trx ‖ sha256(context_free_data)
// from a real serialized transaction (reuse pulsevm-js serialization or a vector).
let preimage = Data("REPLACE_WITH_chain_id||packed_trx||sha256(cfd)".utf8)
let digest = Data(SHA256.hash(data: preimage)) // the value PulseVM recovers against
print("  recovery digest (sha256 preimage): \(hex(digest))")

// --- 3. Sign in hardware (Touch/Face ID prompt) ----------------------------
let sig = try priv.signature(for: preimage)        // ECDSA over SHA256(preimage)
let rs = sig.rawRepresentation                      // 64 bytes: r ‖ s
print("✓ signed in Enclave")
print("  raw r||s (64B): \(hex(rs))")

// --- 4. Make it Antelope-recoverable ---------------------------------------
// TODO(step 4a): normalize to low-s (s = n - s if s > n/2)  [secp256r1 order n]
// TODO(step 4b): derive recovery id — for recid in 0..3, recover the candidate
//   pubkey from (digest, r, s, recid) and pick the one equal to our pubkey.
// TODO(step 4c): assemble compact SIG_R1_… (recid-encoded header ‖ r ‖ s, base58+checksum)
//   Port the canonical + recid + encoding logic from pulsevm-js (do NOT re-derive).

// --- 5. Verify --------------------------------------------------------------
// TODO(step 5): feed (digest, SIG_R1) to PulseVM's recover_public_key (pulsevm_crypto/libfc)
//   and assert it returns our PUB_R1; and/or push a signed tx to A-Chain (when up).

print("\nNext: implement steps 1b, 2, 4, 5 (port encoding/recid from pulsevm-js). See wiki/23.")
