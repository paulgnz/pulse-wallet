import SwiftUI
import AppKit

/// Guided, safety-first key rotation: generate a new key → **back up old + new** →
/// confirm → updateauth. Designed so a user can't accidentally lose account access.
///
/// Two entry points:
///  • Generic ("Rotate Key" button) — replace a permission's authority with a fresh key.
///  • Emergency ("Rotate this key" on a key row) — a specific key may be leaked/compromised;
///    pre-targets the permission it's on and swaps just that key out (keeping co-signers).
struct RotateKeySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(KeyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// When set, this flow is an EMERGENCY rotation of a specific (possibly compromised) key.
    var compromisedKey: WalletKey? = nil

    enum Method: String, CaseIterable, Identifiable {
        case enclave = "Secure Enclave (R1)"
        case softwareR1 = "Software R1"
        case softwareK1 = "Software K1"
        var id: String { rawValue }
    }
    enum Step { case setup, backup, confirm, done }

    @State private var step: Step = .setup
    @State private var method: Method = .softwareR1
    @State private var permission = "active"
    @State private var parent = "owner"

    @State private var newKey: WalletKey?       // generated; already in the wallet
    @State private var newBackup: String?        // software private to save (nil for Enclave)
    @State private var oldBackup: String?        // exported old signing key (optional)
    @State private var ackSaved = false
    @State private var confirmText = ""
    @State private var working = false
    @State private var status: String?
    @State private var txid: String?

    private var rotatingOwner: Bool { permission == "owner" }
    private var isEmergency: Bool { compromisedKey != nil }
    private var currentPerm: Permission? {
        model.account?.permissions.first { $0.permName == permission }
    }
    /// In an emergency, keep the permission's other keys and swap only the bad one.
    /// Otherwise replace the whole authority with the new key (1-of-1).
    private var coSigners: [AuthKey] {
        guard isEmergency, let perm = currentPerm else { return [] }
        return perm.requiredAuth.keys.filter { $0.key != compromisedKey?.pubKey }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            content
            if let status { Text(status).font(.caption).foregroundStyle(Brand.danger) }
            Spacer()
            actions
        }
        .padding(24).frame(width: 500, height: 560)
        .background(BrandBackground())
        .onAppear {
            // Pre-target the permission the compromised key actually sits on.
            if let ck = compromisedKey {
                let perms = model.permissions(forKey: ck.pubKey)
                permission = perms.first ?? "active"
                parent = permission == "owner" ? "owner" : "owner"
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isEmergency ? "Emergency Key Rotation" : "Rotate Key").font(.title2.weight(.semibold))
            Text(stepHint).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var stepHint: String {
        switch step {
        case .setup:
            return isEmergency
                ? "Replace a key that may be leaked or compromised. A new key is generated and the account is updated to drop the old one — fast."
                : "Replace \(model.accountName)’s @\(permission) authority with a freshly generated key. Use this if a key may be exposed, or to refresh keys periodically."
        case .backup:  return "Back up your keys before changing anything on-chain."
        case .confirm: return "Review carefully — this changes who can control the account."
        case .done:    return "Rotation submitted."
        }
    }

    // MARK: Steps

    @ViewBuilder private var content: some View {
        switch step {
        case .setup:   setupStep
        case .backup:  backupStep
        case .confirm: confirmStep
        case .done:    doneStep
        }
    }

    private var setupStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let ck = compromisedKey {
                GlassCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Replacing “\(ck.label)” on @\(permission)", systemImage: "exclamationmark.shield.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(Brand.danger)
                        Text(ck.pubKey).font(.caption2.monospaced()).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        Text(coSigners.isEmpty
                             ? "This key is the only one on @\(permission). It will be replaced by the new key."
                             : "The other \(coSigners.count) key(s) on @\(permission) are kept; only this one is removed.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            field("New key type") {
                Picker("", selection: $method) {
                    ForEach(Method.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().pickerStyle(.menu)
            }
            if isEmergency {
                field("Permission") {
                    Text("@\(permission)").foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    field("Permission") { TextField("active", text: $permission) }
                    field("Parent") { TextField("owner", text: $parent) }
                }
            }
            GlassCard(padding: 12) {
                Label(rotatingOwner
                      ? "You're rotating OWNER — the account's root authority. If you lose the new key you lose the account permanently. Strongly prefer rotating ‘active’ and keeping ‘owner’ as recovery."
                      : "Rotating ‘active’. Your ‘owner’ permission stays unchanged as a recovery path.",
                      systemImage: rotatingOwner ? "exclamationmark.triangle.fill" : "checkmark.shield")
                    .font(.caption).foregroundStyle(rotatingOwner ? Brand.danger : Brand.success)
            }
        }
    }

    private var backupStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let newKey {
                GlassCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("NEW key", systemImage: "key.fill").font(.caption.weight(.semibold)).foregroundStyle(Brand.accent)
                        copyRow("Public", newKey.pubKey)
                        if let newBackup {
                            copyRow("Private — SAVE THIS", newBackup, secret: true)
                            Text("This software key is shown once. Store it in your password manager.")
                                .font(.caption2).foregroundStyle(Brand.warn)
                        } else {
                            Text("Secure Enclave key — the private key is device-bound and can't be exported. If this Mac is lost, you can only recover via the ‘owner’ permission. Keep ‘owner’ on a different key.")
                                .font(.caption2).foregroundStyle(Brand.warn)
                        }
                    }
                }
            }
            GlassCard(padding: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("OLD signing key", systemImage: "key").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if let oldBackup {
                        copyRow("Private", oldBackup, secret: true)
                    } else if store.activeKey?.kind == .imported {
                        Button("Back up current key (Touch ID)") { backupOld() }.buttonStyle(.glass)
                    } else {
                        Text(store.activeKey == nil
                             ? "No active key in this wallet to sign with."
                             : "Current signing key is in the Secure Enclave (not exportable). It stays in your wallet; after rotation it just no longer controls the account.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Toggle(isOn: $ackSaved) {
                Text("I’ve securely saved my new key and have a way to recover this account.")
                    .font(.caption)
            }
        }
    }

    private var confirmStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    row("Account", model.accountName)
                    Divider(); row("Permission", "@\(permission)")
                    Divider()
                    row("New authority", coSigners.isEmpty
                        ? "1-of-1 · \(newKey.map { String($0.pubKey.prefix(16)) } ?? "")…"
                        : "\(currentPerm?.requiredAuth.threshold ?? 1)-of-\(coSigners.count + 1) · keeps \(coSigners.count) co-signer(s) + new key")
                    Divider()
                    row("Signed by", "\(model.accountName)@\(model.permissionName) (current key)")
                }
            }
            if rotatingOwner {
                Label("This replaces the OWNER authority. Triple-check your backup.", systemImage: "exclamationmark.octagon.fill")
                    .font(.caption).foregroundStyle(Brand.danger)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Type CONFIRM to rotate").font(.caption).foregroundStyle(.secondary)
                TextField("CONFIRM", text: $confirmText).pulseField(mono: true)
            }
        }
    }

    private var doneStep: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Rotation submitted", systemImage: "checkmark.seal.fill").foregroundStyle(Brand.success)
                if let txid { Text(txid).font(.caption.monospaced()).textSelection(.enabled).lineLimit(2) }
                Text("The new key is now active in your wallet. Verify the account’s keys updated before relying on it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Actions

    @ViewBuilder private var actions: some View {
        switch step {
        case .setup:
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.glass).controlSize(.large)
                Spacer()
                PrimaryButton(title: working ? "Generating…" : "Generate new key", systemImage: "sparkles") { generate() }
                    .frame(width: 200).disabled(working)
            }
        case .backup:
            HStack {
                Button("Back") { step = .setup }.buttonStyle(.glass).controlSize(.large)
                Spacer()
                PrimaryButton(title: "Continue", systemImage: "arrow.right") { step = .confirm }
                    .frame(width: 160).disabled(!ackSaved)
            }
        case .confirm:
            HStack {
                Button("Back") { step = .backup }.buttonStyle(.glass).controlSize(.large)
                Spacer()
                Button(role: .destructive) { rotate() } label: {
                    Label(working ? "Rotating…" : "Rotate now", systemImage: "arrow.triangle.2.circlepath")
                        .frame(width: 170).padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent).tint(rotatingOwner ? Brand.danger : Brand.primary)
                .controlSize(.large).disabled(working || confirmText != "CONFIRM")
            }
        case .done:
            PrimaryButton(title: "Done", systemImage: "checkmark") { dismiss() }
        }
    }

    // MARK: Logic

    private func generate() {
        working = true
        let perm = permission
        Task {
            do {
                switch method {
                case .enclave:
                    newKey = try store.createEnclaveKey(label: "Rotated \(perm)")
                    newBackup = nil
                case .softwareR1, .softwareK1:
                    let curve: WalletKey.Curve = method == .softwareR1 ? .r1 : .k1
                    let g = KeyToolkit.generate(curve)
                    newBackup = g.privateKey
                    newKey = try store.importKey(secret: g.privateKey,
                                                 label: "Rotated \(curve.rawValue.uppercased())", curve: curve)
                }
                step = .backup
            } catch { status = error.localizedDescription }
            working = false
        }
    }

    private func backupOld() {
        guard let active = store.activeKey else { return }
        Task {
            do { oldBackup = try await store.exportSecret(active, reason: "Back up current key before rotation") }
            catch { status = error.localizedDescription }
        }
    }

    private func rotate() {
        guard model.keyControlsAccount(store.activeKey?.pubKey) else {
            status = "Your current active key doesn't control \(model.accountName) — you can't sign the change. Set a controlling key active first."; return
        }
        guard let ctx = model.taposContext(), let nk = newKey else { status = "Not connected."; return }
        working = true
        let me = model.accountName, perm = permission
        let par = currentPerm?.parent ?? parent
        // Emergency with co-signers: keep them, drop only the bad key, preserve threshold.
        // Otherwise: fresh 1-of-1 authority.
        let keyStr: String
        let threshold: UInt32
        if !coSigners.isEmpty, let cur = currentPerm {
            keyStr = (coSigners.map { "\($0.key)@\($0.weight)" } + ["\(nk.pubKey)@1"]).joined(separator: ";")
            threshold = UInt32(cur.requiredAuth.threshold)
        } else {
            keyStr = "\(nk.pubKey)@1"
            threshold = 1
        }
        Task {
            do {
                let tx = try model.core.buildUpdateAuth(
                    systemContract: "pulse", account: me, permission: perm, parent: par,
                    threshold: threshold, keys: keyStr, authActor: me, authPerm: model.permissionName,
                    chainId: ctx.chainId, refBlockNum: ctx.refBlockNum,
                    refBlockPrefix: ctx.refBlockPrefix, expiration: ctx.expiration)
                guard let preImage = Data(hexString: tx.preimage) else { status = "bad preimage"; working = false; return }
                let sig = try await store.sign(preImage: preImage, reason: "Rotate \(me) \(perm) key")
                txid = try await model.broadcast(signatures: [sig], packedTrx: tx.packed)
                store.activeKeyID = nk.id
                step = .done
                working = false
            } catch { status = error.localizedDescription; working = false }
        }
    }

    // MARK: Bits

    private func field(_ label: String, @ViewBuilder _ c: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            c().pulseField(mono: true)
        }
    }
    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v).fontWeight(.medium).lineLimit(1).truncationMode(.middle) }
    }
    private func copyRow(_ k: String, _ v: String, secret: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(k).font(.caption2.weight(.medium)).foregroundStyle(secret ? Brand.warn : .secondary)
                Spacer()
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(v, forType: .string) }
                    label: { Image(systemName: "doc.on.doc").font(.caption2) }.buttonStyle(.plain)
            }
            Text(v).font(.caption2.monospaced()).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
        }
    }
}
