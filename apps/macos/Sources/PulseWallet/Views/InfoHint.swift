import SwiftUI

/// A small "?" affordance that reveals a plain-language explanation in a popover.
/// Use it next to any term a non-expert might not know (owner vs active, R1/K1, …).
/// Markdown is supported in `text` (e.g. **bold**).
struct InfoHint: View {
    let text: String
    var title: String? = nil
    @State private var show = false

    var body: some View {
        Button { show.toggle() } label: {
            Image(systemName: "questionmark.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(title ?? "Learn more")
        .popover(isPresented: $show, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                if let title {
                    Text(title).font(.subheadline.weight(.semibold))
                }
                Text(.init(text)).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14).frame(width: 300)
        }
    }
}

/// Shared, reusable copy for the concepts the wallet explains in more than one place.
enum Explain {
    static let ownerVsActive = """
    Your account has two main permissions. **@owner** is the master key — it can \
    change everything, including the active key. Keep it offline (YubiKey or paper). \
    **@active** is for day-to-day signing (transfers, staking). If @active is ever \
    compromised, @owner can rotate it.
    """
    static let curves = """
    **R1 (secp256r1)** is the modern curve used by Apple's Secure Enclave and YubiKeys — \
    the private key can live in hardware and never leaves it. **K1 (secp256k1)** is the \
    classic EOSIO/Antelope curve (keys starting `PVT_K1_…`/`5…`). Both work on PulseVM.
    """
    static let signingVsLinked = """
    **Signing key** = the key this wallet currently uses to sign (a local choice). \
    **Linked** = the key is on the account's on-chain permissions, so the network accepts \
    it. A key can be linked but not your signing key, or selected for signing but not yet \
    linked (use “Link to account”).
    """
    static let threshold = """
    A permission can require several keys. **Threshold** is how many key-weights must sign. \
    Threshold 1 with one key = a normal single-signer. Threshold 2 of 3 = a 2-of-3 multisig.
    """
}
