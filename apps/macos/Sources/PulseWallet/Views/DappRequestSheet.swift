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

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Image(systemName: done ? "checkmark.seal.fill" : "link.badge.plus")
                    .font(.system(size: 40)).foregroundStyle(Brand.brandGradient)
                Text(title).font(.title2.weight(.semibold))
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    row("Account", model.accountName)
                    Divider()
                    row("Signing key", keyStore.activeKey?.label ?? "—")
                    if case .sign(_, _, let summary, _) = request {
                        Divider(); row("Request", summary)
                    }
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(Brand.danger).multilineTextAlignment(.center) }
            Spacer()
            actions
        }
        .padding(24).frame(width: 420, height: 380)
        .background(BrandBackground())
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
                    // Login returns the account (and active pubkey if one is held).
                    callback(cb, items: ["account": model.accountName,
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
