# pulse-wallet

A wallet for **PulseVM** networks (A-Chain / XPR Network). Multi-platform by design, with one shared core and native, hardware-backed signing per platform.

## Why a monorepo

The crypto/signing/RPC logic must be **one implementation**, not reimplemented per platform — a single, auditable core. Only the *signer* is platform-specific (each platform's secure hardware).

```
core/        Rust shared core — tx build, key/sig encoding, recovery-id derivation, RPC.
             Exposed via: uniffi → Swift (macOS/iOS), native (Tauri desktop), wasm → web.
apps/
  macos/     SwiftUI + Secure Enclave (P-256 = secp256r1 = PulseVM R1 keys). ← first target
  desktop/   Tauri (Linux/Windows) — later
  web/       web wallet — later
spike/        Secure-Enclave → PulseVM-acceptable signature proof (step zero, see below)
```

## The differentiator

PulseVM supports **R1 (secp256r1)** keys natively — the same curve as Apple/Android **Secure Enclave** and **WebAuthn passkeys**. So the wallet can use **hardware-backed, biometric, non-exportable keys** as real on-chain keys: no seed phrase, Touch/Face-ID to sign. EVM (secp256k1) can't do this natively.

## Step zero: the spike

Before building the app, prove a Secure-Enclave key can sign a transaction PulseVM accepts.
PulseVM **recovers** the pubkey from the signature, so signatures must be *recoverable* — the
Enclave's standard ECDSA needs a client-derived recovery id. See `spike/` and the full plan in
`pulsevm-experimental/wiki/23-wallet-strategy.md`.

## Status
Pre-spike scaffold. Nothing here is production. Key custody is the #1 security surface — any
release needs audit + a recovery/rotation story (PulseVM's account model: a lost key is a
rotation, not a lost account).
