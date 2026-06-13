# Pulse Wallet — macOS

A native SwiftUI wallet for PulseVM, designed with current macOS (Tahoe / Liquid
Glass) components: `NavigationSplitView`, `glassEffect`, `GlassEffectContainer`,
`.buttonStyle(.glass)` / `.glassProminent`, SF Symbols, and `@Observable` state.

## Open it

```sh
cd apps/macos
xcodegen generate          # regenerates PulseWallet.xcodeproj from project.yml
open PulseWallet.xcodeproj
```

`project.yml` is the source of truth — the `.xcodeproj` is generated, so commit
the spec and regenerate rather than hand-editing the project. Requires
`brew install xcodegen`. Builds clean today against macOS 26 / Swift 6.

In Xcode, set your **Development Team** under Signing & Capabilities, then run on
a Mac with Apple silicon or a T2 chip to exercise the Enclave path.

> **Required:** a Development Team must be selected. The `keychain-access-groups`
> entitlement uses `$(AppIdentifierPrefix)`, which only resolves with a real team.
> Without one, the app is signed ad-hoc and `libsecinit` traps at launch
> (`EXC_BREAKPOINT` in `_libsecinit_appsandbox`). If you want team-free local
> builds, remove the `keychain-access-groups` block from
> `Resources/PulseWallet.entitlements` — Secure Enclave keys don't require it for
> a single standalone app.

## Layout

```
Sources/PulseWallet/
  PulseWalletApp.swift     @main App, menu commands, Settings scene
  AppModel.swift           @Observable app state (WalletSection, accounts, assets)
  Models/                  PulseAccount, Asset, ActivityItem
  Design/Theme.swift       brand palette (navy/electric) + metrics
  Views/                   RootView (split nav), Sidebar, Dashboard, Send,
                           Receive, Activity, Settings, LockScreen, Components
  Crypto/
    EnclaveSigner.swift    Secure Enclave keygen + raw r‖s signing (real CryptoKit)
    PulseCore.swift        protocol bridge to the Rust core (stub until uniffi)
```

## Architecture seam

**core = chain logic, signer = platform.** All chain-exact logic lives in the
shared Rust crate `../../core` (`pulse-wallet-core`):

- recovery-id derivation + `SIG_R1` assembly — **validated byte-for-byte vs
  pulsevm-js** (`cargo test` green)
- `PUB_R1` encoding
- transaction serialization + signing digest (next)
- RPC / REST client (next)

`EnclaveSigner` only owns the chip: it generates a biometric-gated P-256 key in
the Secure Enclave and produces a raw, non-recoverable `r‖s`. The Rust core
derives the recovery id (by recover-and-match) and assembles the PulseVM-acceptable
signature. CryptoKit cannot recover a public key, which is exactly why that step
lives in Rust.

## Status

- ✅ UI scaffold builds and runs against `PulseCoreStub` (sample state).
- ✅ Secure Enclave keygen + signing implemented (CryptoKit).
- ⏳ uniffi binding to expose `pulse-wallet-core` to Swift, then swap
  `PulseCoreStub` → `PulseCoreFFI` in `AppModel`.
- ⏳ live transfer: build digest in core → sign pre-image in Enclave → assemble
  `SIG_R1` in core → push to RPC. (Deferred end-to-end until A-Chain is back up;
  the SIG_R1 path is already proven locally against pulsevm-js.)

MVP scope: create/import key → sign → send → balances/history (Hyperion) →
msig propose/approve. Distribute as a notarized .dmg (App Store crypto-wallet
policies are restrictive).
