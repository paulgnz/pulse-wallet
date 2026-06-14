import SwiftUI

/// Add a YubiKey: read the P-256 (R1) public key from a PIV slot. The private key
/// stays on the device; signing later uses the PIV PIN.
struct AddYubiKeySheet: View {
    @Environment(KeyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var error: String?

    @State private var slot: UInt8 = 0x9a
    @State private var label = ""
    @State private var pin = ""
    @State private var generate = false
    @State private var working = false
    @State private var localError: String?

    private var present: Bool { YubiKeyPIV.isPresent() }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 8) {
                Image(systemName: "key.radiowaves.forward").font(.system(size: 36))
                    .foregroundStyle(Brand.brandGradient)
                Text("Add YubiKey").font(.title2.weight(.semibold))
                Text("Reads the P-256 (R1) public key from a PIV slot. The private key never leaves the YubiKey; signing needs your PIV PIN.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            HStack(spacing: 6) {
                Circle().fill(present ? Brand.success : Brand.danger).frame(width: 8, height: 8)
                Text(present ? "YubiKey detected" : "No YubiKey detected — insert it and reopen")
                    .font(.caption).foregroundStyle(.secondary)
            }
            labeled("Slot") {
                Picker("", selection: $slot) {
                    ForEach(YubiKeyPIV.slots, id: \.0) { Text($0.1).tag($0.0) }
                }.labelsHidden().pickerStyle(.menu)
            }
            Text("A “slot” is a key storage location on the YubiKey. Any works — **Authentication (9a)** is the standard choice. Each slot holds one key.")
                .font(.caption2).foregroundStyle(.secondary)
            Toggle(isOn: $generate) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Generate a new key in this slot").font(.callout)
                    Text(generate ? "⚠︎ Overwrites any existing key in the slot. Uses the default PIV management key."
                                  : "Off = read the key already in the slot.")
                        .font(.caption2).foregroundStyle(generate ? Brand.warn : .secondary)
                }
            }
            labeled("Label") { TextField("YubiKey", text: $label).pulseField() }
            labeled("PIV PIN (optional — caches it for signing this session)") {
                SecureField("PIN", text: $pin).pulseField(mono: true)
            }
            if let e = localError ?? error { Text(e).font(.caption).foregroundStyle(Brand.danger) }
            Spacer()
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.glass).controlSize(.large)
                Spacer()
                PrimaryButton(title: working ? (generate ? "Generating…" : "Reading…") : (generate ? "Generate & Add" : "Add"),
                              systemImage: generate ? "sparkles" : "plus") { add() }
                    .frame(width: 180).disabled(working || !present)
            }
        }
        .padding(24).frame(width: 460, height: 470)
        .background(BrandBackground())
    }

    private func labeled(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            content()
        }
    }

    private func add() {
        working = true; localError = nil; error = nil
        Task {
            do {
                try await store.addYubiKey(slot: slot, label: label, generate: generate)
                if !pin.isEmpty { store.sessionYubiPIN = pin }
                working = false
                dismiss()
            } catch {
                localError = error.localizedDescription
                working = false
            }
        }
    }
}

/// Enter the PIV PIN, cached in memory for the session so the YubiKey can sign.
struct UnlockYubiKeySheet: View {
    @Environment(KeyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.open").font(.system(size: 34)).foregroundStyle(Brand.brandGradient)
            Text("Unlock YubiKey").font(.title2.weight(.semibold))
            Text("Enter your PIV PIN. It's held in memory for this session so the YubiKey can sign — never written to disk.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            SecureField("PIV PIN", text: $pin).pulseField(mono: true)
            Spacer()
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.glass).controlSize(.large)
                Spacer()
                PrimaryButton(title: "Unlock", systemImage: "lock.open") {
                    store.sessionYubiPIN = pin; dismiss()
                }.frame(width: 150).disabled(pin.isEmpty)
            }
        }
        .padding(24).frame(width: 420, height: 320)
        .background(BrandBackground())
    }
}

/// Link a key to an account permission: `updateauth` that ADDS this key to the
/// permission (keeping its existing keys), signed by the current active key.
struct LinkKeySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(KeyStore.self) private var keyStore
    @Environment(\.dismiss) private var dismiss
    let key: WalletKey

    @State private var permission = "active"
    @State private var working = false
    @State private var done = false
    @State private var status: String?

    private var currentPerm: Permission? {
        model.account?.permissions.first { $0.permName == permission }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Link key to account").font(.title2.weight(.semibold))
            Text("Adds this key to \(model.accountName)’s permission via updateauth, signed by your current active key. Existing keys are kept.")
                .font(.caption).foregroundStyle(.secondary)

            labeled("Key") {
                Text(key.pubKey).font(.caption.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
            labeled("Permission") { TextField("active", text: $permission).pulseField(mono: true) }

            if let perm = currentPerm {
                Text("Current: \(perm.requiredAuth.keys.count) key(s), threshold \(perm.requiredAuth.threshold) → adds 1 (threshold unchanged).")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Permission “\(permission)” not found on \(model.accountName) yet — load the account first.")
                    .font(.caption2).foregroundStyle(Brand.warn)
            }

            if let status {
                Text(status).font(.caption)
                    .foregroundStyle(status.hasPrefix("Submitted") ? Brand.success : Brand.danger)
                    .textSelection(.enabled)
            }
            Spacer()
            if done {
                PrimaryButton(title: "Done", systemImage: "checkmark") { dismiss() }
            } else {
                HStack {
                    Button("Cancel") { dismiss() }.buttonStyle(.glass).controlSize(.large)
                    Spacer()
                    PrimaryButton(title: working ? "Linking…" : "Link (updateauth)", systemImage: "link") { submit() }
                        .frame(width: 220).disabled(working || currentPerm == nil)
                }
            }
        }
        .padding(24).frame(width: 480, height: 430)
        .background(BrandBackground())
    }

    private func labeled(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            content()
        }
    }

    private func submit() {
        guard model.keyControlsAccount(keyStore.activeKey?.pubKey) else {
            status = "Your active key doesn’t control \(model.accountName). Set a controlling key active first."; return
        }
        guard let ctx = model.taposContext(), let perm = currentPerm else {
            status = "Not connected, or permission not found."; return
        }
        // Keep existing keys, append this one (weight 1) if not already present.
        var entries = perm.requiredAuth.keys.map { "\($0.key)@\($0.weight)" }
        if !entries.contains(where: { $0.hasPrefix(key.pubKey + "@") }) {
            entries.append("\(key.pubKey)@1")
        }
        let keyStr = entries.joined(separator: ";")
        let parent = perm.parent
        let threshold = UInt32(perm.requiredAuth.threshold)
        let me = model.accountName
        working = true
        Task {
            do {
                let tx = try model.core.buildUpdateAuth(
                    systemContract: "pulse", account: me, permission: permission, parent: parent,
                    threshold: threshold, keys: keyStr, authActor: me, authPerm: model.permissionName,
                    chainId: ctx.chainId, refBlockNum: ctx.refBlockNum,
                    refBlockPrefix: ctx.refBlockPrefix, expiration: ctx.expiration)
                guard let preImage = Data(hexString: tx.preimage) else { status = "bad preimage"; working = false; return }
                let sig = try await keyStore.sign(preImage: preImage, reason: "Link key to \(me)@\(permission)")
                _ = try await model.broadcast(signatures: [sig], packedTrx: tx.packed)
                status = model.networkPaused
                    ? "Submitted ✓ — queued. The chain is paused, so it applies once validators resume."
                    : "Submitted ✓ — \(key.pubKey.prefix(16))… added to \(me)@\(permission)."
                done = true
                working = false
            } catch {
                status = error.localizedDescription
                working = false
            }
        }
    }
}
