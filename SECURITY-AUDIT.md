# PulseVM Wallet — Security Audit

_Internal review of the native macOS PulseVM wallet. Last updated 2026-06-14._

This document describes the wallet's security architecture, dependency posture,
threat model, and known caveats. It reflects a code-level review of the key
custody, signing, and storage paths.

---

## 1. Scope & architecture

The wallet is two components — **no JavaScript / npm in the key-handling app**:

| Layer | Language | Responsibility |
|-------|----------|----------------|
| UI / app | Swift (SwiftUI, macOS 26) | Views, account state, RPC, transaction assembly orchestration |
| Crypto core | Rust (static lib, C ABI) | Key encoding, signature assembly (SIG_R1 / SIG_K1), tx (de)serialization |

The separate **`pulse-web-sdk`** (TypeScript/npm) is a *dapp connector* that runs
in third-party websites. It **never has access to private keys** — it only hands
an unsigned transaction to the wallet over the `pulsevm://` URL scheme and
receives a signature back. It is outside the trust boundary of key custody.

---

## 2. Key custody

Two key types, both hardware-rooted in the Secure Enclave:

### Secure Enclave (R1) keys — preferred
- Private key is **generated inside the Secure Enclave and is non-extractable**.
  The app never sees the private key material.
- Access control: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` +
  `[.privateKeyUsage, .biometryCurrentSet]` — Touch ID required for every use,
  and the key is **invalidated if the enrolled biometric set changes**.
- Only the Enclave's device-bound key *handle* (`dataRepresentation`) is written
  to disk. It is meaningless on any other device.

### Imported keys (R1 / K1) — for existing accounts
- Raw private key is **encrypted with AES-GCM**. The symmetric key is derived
  (HKDF-SHA256) from an ECDH key agreement against a **Secure Enclave
  key-agreement key**. Encryption uses the Enclave public key (no prompt);
  **decryption runs the Enclave private key and requires Touch ID**.
- The Enclave wrapping key uses the same `.biometryCurrentSet` access control.

### Storage location
- Key material lives as files under
  `~/Library/Application Support/PulseVM/keys/` — **not** the login keychain.
  This deliberately avoids the keychain's password-ACL prompts; biometric
  enforcement is provided by the Enclave instead.
- Keys are **never** stored in plaintext, in `UserDefaults`, or transmitted off
  the device. Only **signatures** (public data) are sent to the RPC endpoint.

### What leaves the device
- Public keys, signatures, and packed transactions — all public.
- **No private key, seed, or decrypted secret ever leaves the device.**

---

## 3. Signing path

1. The unsigned transaction is serialized and a SHA-256 pre-image/digest formed.
2. One **Touch ID** authorization per signature:
   - Enclave keys: the Enclave signs the digest directly.
   - Imported keys: Touch ID unwraps the AES-GCM secret, then the Rust core signs.
3. K1 signatures are produced with a canonical-form retry loop (high-bit r/s rule)
   so the chain accepts them.
4. The assembled `SIG_R1` / `SIG_K1` is returned and broadcast.

The "enter password" option that may appear is the **standard fallback inside the
Touch ID sheet**, not a login-keychain prompt — key files are not in the keychain.

---

## 4. Dependencies

### Rust crypto core (`cargo audit`)
`cargo audit` against the RustSec advisory DB (1131 advisories):
**0 vulnerabilities across 52 crate dependencies.**

Direct dependencies are the standard, widely-used RustCrypto stack:

| Crate | Purpose |
|-------|---------|
| `p256` | secp256r1 (R1) ECDSA |
| `k256` | secp256k1 (K1) ECDSA |
| `ecdsa` | ECDSA primitives |
| `rand_core` (getrandom) | CSPRNG for nonces |
| `sha2`, `ripemd` | hashing (digests, key/address checksums) |
| `bs58`, `hex` | key/signature encoding |
| `serde_json` | tx decode output |

### Swift app
- No third-party Swift packages in the key path; uses Apple frameworks only
  (`CryptoKit`, `LocalAuthentication`, `Security`, SwiftUI/AppKit).

> Re-run dependency audit: `cd core && cargo audit`.

---

## 5. Distribution integrity

- **Hardened Runtime** enabled.
- Signed with a **Developer ID Application** certificate and **notarized by Apple**
  (stapled ticket) — tamper-evident; Gatekeeper verifies on launch.
- **Entitlements are empty** — no `get-task-allow`, no debug entitlements in the
  shipped build.

---

## 6. Threat model & residual risks

| Threat | Mitigation |
|--------|------------|
| Device theft (locked) | Keys are `…WhenUnlockedThisDeviceOnly` + biometric; unusable while locked. |
| Key exfiltration | Enclave keys are non-extractable; imported keys are encrypted and need the Enclave (Touch ID) to decrypt. |
| Malware reading key files | Encrypted blobs are useless without the Enclave key, which is biometric-gated. |
| Tampered binary | Notarization + hardened runtime + code signature. |
| Network MITM | Read calls only fetch public state; signatures are over the canonical tx digest, so a swapped payload produces an invalid signature. Use HTTPS endpoints. |
| Blind signing | Decode-before-sign (dapp) and decode-before-approve (multisig) render the real actions before any signature. |
| Elevated-permission misuse | Signing defaults to `active`; using `owner` triggers a red window frame + banner. |

### Known caveats / hardening backlog
- **Imported keys are exportable** (with Touch ID) by design, for backup. For
  highest assurance, use **Secure Enclave keys** (non-extractable) on high-value
  accounts.
- **No App Sandbox** today (empty entitlements). A user-level process cannot
  decrypt the key blobs (Enclave-gated), but enabling the **App Sandbox** would
  add defense-in-depth around file access. _Tracked as a hardening item._
- `.biometryCurrentSet` invalidates Enclave keys if the fingerprint set changes —
  a security feature, but users must keep a backup (imported key / multisig
  co-signer) to avoid lockout.
- TLS certificate pinning is not yet implemented for RPC endpoints.

---

## 7. Summary

Private keys are hardware-rooted in the Secure Enclave, biometric-gated, never
leave the device, and are never held in plaintext. The crypto core has no known
vulnerable dependencies. The shipped app is signed, notarized, and hardened.
The main hardening opportunities are enabling the App Sandbox and TLS pinning;
the main user guidance is to prefer non-extractable Enclave keys for high-value
accounts.
