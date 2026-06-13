import SwiftUI
import AppKit

/// An incoming dapp request via the pulsevm:// URL scheme.
enum DappRequest: Identifiable, Sendable {
    case login(callback: URL?)
    case sign(chainId: String, packedTrx: String, summary: String, callback: URL?)

    var id: String {
        switch self {
        case .login(let cb): return "login:\(cb?.absoluteString ?? "")"
        case .sign(_, let p, _, _): return "sign:\(p.prefix(16))"
        }
    }
    var callback: URL? {
        switch self {
        case .login(let cb): return cb
        case .sign(_, _, _, let cb): return cb
        }
    }
}

/// Approval UI for a dapp login/sign request — the desktop end of the SDK.
struct DappRequestSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(KeyStore.self) private var keyStore
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    let request: DappRequest

    @State private var working = false
    @State private var error: String?
    @State private var done = false
    @State private var decoded: DecodedTx?
    @State private var decodeFailed = false

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Image(systemName: done ? "checkmark.seal.fill" : "link.badge.plus")
                    .font(.system(size: 40)).foregroundStyle(Brand.brandGradient)
                Text(title).font(.title2.weight(.semibold))
            }

            if isSign, let mismatch = chainMismatch {
                warningBanner(mismatch)
            }

            ScrollView {
                VStack(spacing: 12) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            row("Account", model.accountName)
                            Divider()
                            row("Signing key", keyStore.activeKey?.label ?? "—")
                        }
                    }
                    if isSign { signDetail }
                }
            }
            .frame(maxHeight: .infinity)

            if let error { Text(error).font(.caption).foregroundStyle(Brand.danger).multilineTextAlignment(.center) }
            actions
        }
        .padding(24).frame(width: 460, height: isSign ? 560 : 360)
        .background(BrandBackground())
        .task {
            if case .sign(_, let packed, _, _) = request {
                if let d = model.core.decodeTransaction(packedTrx: packed) { decoded = d }
                else { decodeFailed = true }
            }
        }
    }

    private var isSign: Bool { if case .sign = request { return true }; return false }

    /// Returns (requestChain, walletChain) when they differ — nil when they match or unknown.
    private var chainMismatch: (req: String, wallet: String)? {
        guard case .sign(let chainId, _, _, _) = request, !chainId.isEmpty else { return nil }
        guard let wallet = model.networks.active.chainId ?? model.chainInfo?.chainId, !wallet.isEmpty
        else { return nil }
        return chainId == wallet ? nil : (chainId, wallet)
    }

    @ViewBuilder private var signDetail: some View {
        if let decoded {
            ForEach(decoded.actions) { action in ActionCard(action: action) }
            GlassCard(padding: 12) {
                row("Expires", expirationText(decoded.expiration))
            }
        } else if decodeFailed {
            // Couldn't decode — fall back to the dapp-supplied summary, clearly labeled.
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Could not decode this transaction", systemImage: "exclamationmark.triangle")
                        .font(.callout.weight(.semibold)).foregroundStyle(Brand.warn)
                    if case .sign(_, _, let summary, _) = request {
                        Text(summary).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Only sign if you trust this dapp — the contents can't be verified.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        } else {
            ProgressView("Decoding…").frame(maxWidth: .infinity).padding()
        }
    }

    private func warningBanner(_ m: (req: String, wallet: String)) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text("Different network").font(.callout.weight(.semibold))
                Text("Built for chain \(m.req.prefix(8))… but you're on \(m.wallet.prefix(8))…")
                    .font(.caption2.monospaced())
            }
            Spacer()
        }
        .padding(12).foregroundStyle(Brand.danger)
        .background(Brand.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private func expirationText(_ secsSinceEpoch: UInt32) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(secsSinceEpoch))
        let fmt = DateFormatter(); fmt.dateStyle = .none; fmt.timeStyle = .medium
        return fmt.string(from: date)
    }

    private var title: String {
        if done { return "Approved" }
        switch request {
        case .login: return "Connect to dapp"
        case .sign: return "Approve transaction"
        }
    }

    @ViewBuilder private var actions: some View {
        if done {
            PrimaryButton(title: "Done", systemImage: "checkmark") { dismiss() }
        } else if working {
            ProgressView().controlSize(.large)
        } else {
            HStack {
                Button("Reject") { dismiss() }.buttonStyle(.glass).controlSize(.large)
                PrimaryButton(title: actionTitle, systemImage: "touchid") { approve() }
            }
        }
    }

    private var actionTitle: String {
        switch request {
        case .login: return "Connect"
        case .sign:  return "Sign with Touch ID"
        }
    }

    private func approve() {
        working = true
        Task {
            do {
                switch request {
                case .login(let cb):
                    // Login returns the account, the permission the key controls, and its pubkey.
                    callback(cb, items: ["account": model.accountName,
                                         "permission": model.permissionName,
                                         "key": keyStore.activeKey?.pubKey ?? ""])
                case .sign(let chainId, let packed, _, let cb):
                    let material = try model.core.signingMaterial(packedTrx: packed, chainId: chainId)
                    guard let preImage = Data(hexString: material.preimage) else {
                        throw PulseCoreError.signing("bad preimage")
                    }
                    let sig = try await keyStore.sign(preImage: preImage, reason: "Sign dapp transaction")
                    callback(cb, items: ["signature": sig])
                }
                done = true
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }

    private func callback(_ url: URL?, items: [String: String]) {
        guard let url, var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        var q = comps.queryItems ?? []
        q.append(contentsOf: items.map { URLQueryItem(name: $0.key, value: $0.value) })
        comps.queryItems = q
        if let final = comps.url { NSWorkspace.shared.open(final) }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(.secondary); Spacer()
            Text(v).fontWeight(.medium).lineLimit(1).truncationMode(.middle) }
    }
}

/// Renders one decoded action — transfers get a friendly summary; everything
/// else shows account::name + the raw data so nothing is hidden.
private struct ActionCard: View {
    let action: DecodedTx.Action

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: icon).foregroundStyle(Brand.accent)
                    Text("\(action.account) · \(action.name)")
                        .font(.callout.weight(.semibold).monospaced())
                    Spacer()
                }
                if let t = action.transfer {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(t.quantity).font(.title3.weight(.bold))
                            Spacer()
                        }
                        Text("\(t.from)  →  \(t.to)").font(.caption.monospaced()).foregroundStyle(.secondary)
                        if !t.memo.isEmpty {
                            Text("memo: \(t.memo)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("data: \(dataPreview)").font(.caption2.monospaced())
                        .foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                }
                if !action.authorization.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(action.authorization.indices, id: \.self) { i in
                            let a = action.authorization[i]
                            Text("\(a.actor)@\(a.permission)")
                                .font(.caption2.monospaced())
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(.secondary.opacity(0.15), in: .capsule)
                        }
                    }
                }
            }
        }
    }

    private var icon: String {
        if action.transfer != nil { return "arrow.left.arrow.right" }
        switch action.name {
        case "updateauth", "deleteauth", "linkauth", "unlinkauth": return "key.fill"
        case "delegatebw", "undelegatebw", "refund": return "bolt.fill"
        case "buyram", "buyrambytes", "sellram": return "memorychip"
        default: return "doc.text"
        }
    }
    private var dataPreview: String {
        action.dataHex.isEmpty ? "(none)" : "0x" + action.dataHex
    }
}
