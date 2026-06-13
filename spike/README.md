# spike — Secure Enclave → PulseVM R1 signature

Proves a Secure-Enclave key can sign a transaction PulseVM accepts, before building the app.
Run: `swift run EnclaveSpike` (needs a Mac with a Secure Enclave; will prompt Touch ID).

Status: steps 1–3 implemented (Enclave keygen, pubkey export, hardware sign). Steps 4–5 (low-s,
recovery-id derivation, SIG_R1 encoding, verify) are TODO — port the canonical/recid/encoding
logic from **pulsevm-js** rather than re-deriving it. Full plan: `pulsevm-experimental/wiki/23`.

Key fact (from PulseVM source): signatures are verified by *recovering* the pubkey
(`crypto/signature.rs::recover_public_key`), so they MUST carry a recovery id — that's the
whole point of step 4. GREEN = recovered key matches our PUB_R1 / tx accepted.
