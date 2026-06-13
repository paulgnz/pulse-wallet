# core — shared Rust wallet core (planned)

Single implementation of the chain-facing logic, reused by every platform:
- transaction serialization + the Antelope signing digest (sha256(chain_id ‖ packed_trx ‖ cfd))
- key encoding: PUB_R1 / PVT_R1 (base58 + ripemd160 checksum)
- **recovery-id derivation** + canonical (low-s) signature → SIG_R1 compact format
- RPC client (pulsevm.* + REST), table reads, account/permission queries

Exposed via: `uniffi` (Swift bindings for macOS/iOS), native crate (Tauri desktop), `wasm-bindgen` (web).
Signing itself is NOT here — it's delegated to each platform's secure hardware (see apps/).
Reference implementation to port: pulsevm-js (key + signature encoding, canonical/recid logic).

Build this out AFTER the spike is GREEN.
