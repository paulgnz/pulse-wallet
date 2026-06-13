# apps/macos — SwiftUI wallet (first target)

- Keys live in the **Secure Enclave** (CryptoKit `SecureEnclave.P256.Signing`); Touch/Face-ID to sign.
- Chain logic comes from `core/` (via uniffi) once it exists; during the spike, logic is inline.
- MVP scope: create/import key → sign → send → balances/history (Hyperion) → msig propose/approve.
- Distribute as a notarized .dmg (App Store crypto-wallet policies are restrictive).
Create the Xcode/SwiftUI project here once the spike (../spike) is GREEN.
