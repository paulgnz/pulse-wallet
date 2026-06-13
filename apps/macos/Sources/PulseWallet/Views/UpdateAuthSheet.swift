import SwiftUI

/// Set an account permission to an N-of-M weighted-key authority (updateauth).
struct UpdateAuthSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(KeyStore.self) private var keyStore
    @Environment(\.dismiss) private var dismiss

    @State private var permission = "active"
    @State private var parent = "owner"
    @State private var threshold = "1"
    @State private var keys = ""
    @State private var working = false
    @State private var status: String?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set Account Keys").font(.title2.weight(.semibold))
            Text("Replace the authority of \(model.accountName)’s permission with a threshold of weighted keys. Signed by your active key — be careful not to lock yourself out.")
                .font(.caption).foregroundStyle(.secondary)

            field("Permission") { TextField("active", text: $permission) }
            HStack {
                field("Parent") { TextField("owner", text: $parent) }
                field("Threshold") { TextField("1", text: $threshold) }.frame(width: 120)
            }
            field("Keys (PUB_…@weight; one per line is fine)") {
                TextEditor(text: $keys)
                    .font(.caption.monospaced()).frame(height: 90)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            }
            Button("Use my held keys (weight 1)") { fillFromKeyStore() }
                .buttonStyle(.link).font(.caption)

            if let status { Text(status).font(.caption).foregroundStyle(status.hasPrefix("Submitted") ? Brand.success : Brand.danger) }
            Spacer()
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.glass).controlSize(.large)
                Spacer()
                PrimaryButton(title: working ? "Working…" : "Update Authority", systemImage: "checkmark.shield") { submit() }
                    .frame(width: 210)
                    .disabled(working || keys.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(width: 480, height: 520)
        .background(Brand.navy.gradient.opacity(0.5))
        .onAppear { if !loaded { prefillFromChain(); loaded = true } }
    }

    private func field(_ label: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            content().textFieldStyle(.roundedBorder)
        }
    }

    /// Pre-fill from the account's current on-chain permission keys.
    private func prefillFromChain() {
        guard let perm = model.account?.permissions.first(where: { $0.permName == permission }) else { return }
        threshold = String(perm.requiredAuth.threshold)
        keys = perm.requiredAuth.keys.map { "\($0.key)@\($0.weight)" }.joined(separator: ";\n")
    }

    private func fillFromKeyStore() {
        let normalize = keyStore.keys.map { "\($0.pubKey)@1" }
        keys = normalize.joined(separator: ";\n")
    }

    private func submit() {
        guard let ctx = model.taposContext(), let th = UInt32(threshold.trimmingCharacters(in: .whitespaces)) else {
            status = "Not connected or bad threshold."; return
        }
        working = true
        let me = model.accountName
        let keyStr = keys.replacingOccurrences(of: "\n", with: "")
        Task {
            do {
                let tx = try model.core.buildUpdateAuth(
                    systemContract: "pulse", account: me, permission: permission, parent: parent,
                    threshold: th, keys: keyStr, authActor: me, authPerm: "owner",
                    chainId: ctx.chainId, refBlockNum: ctx.refBlockNum,
                    refBlockPrefix: ctx.refBlockPrefix, expiration: ctx.expiration)
                guard let preImage = Data(hexString: tx.preimage) else { status = "bad preimage"; working = false; return }
                let sig = try await keyStore.sign(preImage: preImage, reason: "Update \(me) authority")
                let txid = try await model.broadcast(signatures: [sig], packedTrx: tx.packed)
                status = "Submitted: \(txid)"
                working = false
            } catch {
                status = error.localizedDescription
                working = false
            }
        }
    }
}
