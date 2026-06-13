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

/// A relay return target — when present, the wallet POSTs the result to
/// `<base>/result/<rid>` instead of opening a browser callback tab (seamless).
struct RelayTarget: Sendable {
    let base: String
    let rid: String
}

/// Wraps a request with a unique id so each `.sheet(item:)` presentation is a
/// fresh view. Without this, two logins share the same DappRequest.id, and
/// SwiftUI reuses the previous sheet's @State — showing a stale "Approved"
/// screen and leaving the request unprocessed.
struct PendingRequest: Identifiable, Sendable {
    let id = UUID()
    let request: DappRequest
    var relay: RelayTarget? = nil
}

/// Approval UI for a dapp login/sign request — the desktop end of the SDK.
struct DappRequestSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(KeyStore.self) private var keyStore
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    let request: DappRequest
    var relay: RelayTarget? = nil

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
                    // Confirm the user is present before releasing their identity to
                    // the dapp (matches the Touch ID affordance on the button).
                    let ok = await Biometrics.authenticate(reason: "Connect \(model.accountName) to this dapp")
                    if !ok { working = false; return }
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
                // Relay flow does no browser navigation, so the wallet stays
                // frontmost — step aside and return focus to the dapp's browser.
                if relay != nil {
                    dismiss()
                    NSApp.hide(nil)
                }
            } catch {
                self.error = FriendlyError.explain(error, paused: model.networkPaused).errorDescription
            }
            working = false
        }
    }

    private func callback(_ url: URL?, items: [String: String]) {
        // Seamless path: POST the result to the relay (no browser tab). The dapp
        // polls the relay for it. Falls back to a browser callback if no relay.
        if let relay {
            postToRelay(relay, items: items)
            return
        }
        guard let url, var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        var q = comps.queryItems ?? []
        q.append(contentsOf: items.map { URLQueryItem(name: $0.key, value: $0.value) })
        comps.queryItems = q
        if let final = comps.url { NSWorkspace.shared.open(final) }
    }

    private func postToRelay(_ relay: RelayTarget, items: [String: String]) {
        let base = relay.base.hasSuffix("/") ? String(relay.base.dropLast()) : relay.base
        guard let url = URL(string: "\(base)/result/\(relay.rid)"),
              let body = try? JSONSerialization.data(withJSONObject: items) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = body
        URLSession.shared.dataTask(with: req).resume()
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(.secondary); Spacer()
            Text(v).fontWeight(.medium).lineLimit(1).truncationMode(.middle) }
    }
}

