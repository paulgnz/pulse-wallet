import SwiftUI

/// Rotate an account's permission to a freshly-generated key (updateauth),
/// signed by the current authority. The new key becomes active on success.
struct RotateKeySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(KeyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    enum Method: String, CaseIterable, Identifiable {
        case enclave = "Secure Enclave (R1)"
        case softwareR1 = "Software R1"
        case softwareK1 = "Software K1"
        var id: String { rawValue }
    }

    @State private var method: Method = .enclave
    @State private var permission = "active"
    @State private var parent = "owner"
    @State private var working = false
    @State private var status: String?
    @State private var newPub: String?
    @State private var backup: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rotate Key").font(.title2.weight(.semibold))
            Text("Generate a new key and replace \(model.accountName)’s permission with it. Signed by your current key — make sure it controls the parent permission, or you'll lose access.")
                .font(.caption).foregroundStyle(.secondary)

            field("New key type") {
                Picker("", selection: $method) {
                    ForEach(Method.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().pickerStyle(.menu)
            }
            HStack {
                field("Permission") { TextField("active", text: $permission) }
                field("Parent") { TextField("owner", text: $parent) }
            }

            if let newPub {
                GlassCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("New key", systemImage: "key.fill").font(.caption.weight(.semibold)).foregroundStyle(Brand.success)
                        Text(newPub).font(.caption.monospaced()).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
                        if let backup {
                            Text("Back up the private key now:").font(.caption2).foregroundStyle(Brand.warn)
                            Text(backup).font(.caption2.monospaced()).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
                        }
                    }
                }
            }
            if let status {
                Text(status).font(.caption)
                    .foregroundStyle(status.hasPrefix("Submitted") ? Brand.success : Brand.danger)
            }
            Spacer()
            HStack {
                Button(newPub == nil ? "Cancel" : "Done") { dismiss() }
                    .buttonStyle(.glass).controlSize(.large)
                if newPub == nil {
                    Spacer()
                    PrimaryButton(title: working ? "Rotating…" : "Generate & Rotate", systemImage: "arrow.triangle.2.circlepath") { rotate() }
                        .frame(width: 210).disabled(working)
                }
            }
        }
        .padding(24).frame(width: 480, height: 480)
        .background(BrandBackground())
    }

    private func field(_ label: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            content().textFieldStyle(.roundedBorder)
        }
    }

    private func rotate() {
        guard let ctx = model.taposContext() else { status = "Not connected."; return }
        working = true
        let me = model.accountName
        let perm = permission, par = parent
        Task {
            do {
                // 1. create the new key (old active key stays active until we swap)
                let newKey: WalletKey
                var backupPvt: String?
                switch method {
                case .enclave:
                    newKey = try store.createEnclaveKey(label: "Rotated \(perm)")
                case .softwareR1, .softwareK1:
                    let curve: WalletKey.Curve = method == .softwareR1 ? .r1 : .k1
                    let g = KeyToolkit.generate(curve)
                    backupPvt = g.privateKey
                    newKey = try store.importKey(secret: g.privateKey, label: "Rotated \(curve.rawValue.uppercased())", curve: curve)
                }
                // 2. updateauth → permission := { threshold 1, [newKey@1] }, signed by current key
                let tx = try model.core.buildUpdateAuth(
                    systemContract: "pulse", account: me, permission: perm, parent: par,
                    threshold: 1, keys: "\(newKey.pubKey)@1", authActor: me, authPerm: "owner",
                    chainId: ctx.chainId, refBlockNum: ctx.refBlockNum,
                    refBlockPrefix: ctx.refBlockPrefix, expiration: ctx.expiration)
                guard let preImage = Data(hexString: tx.preimage) else { status = "bad preimage"; working = false; return }
                let sig = try await store.sign(preImage: preImage, reason: "Rotate \(me) \(perm) key")
                let txid = try await model.broadcast(signatures: [sig], packedTrx: tx.packed)
                // 3. swap active key locally
                store.activeKeyID = newKey.id
                newPub = newKey.pubKey
                backup = backupPvt
                status = "Submitted: \(txid)"
                working = false
            } catch {
                status = error.localizedDescription
                working = false
            }
        }
    }
}
