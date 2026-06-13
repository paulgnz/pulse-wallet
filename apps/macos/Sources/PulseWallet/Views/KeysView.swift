import SwiftUI

struct KeysView: View {
    @Environment(KeyStore.self) private var store
    @Environment(AppModel.self) private var model

    @State private var showNew = false
    @State private var showImport = false
    @State private var toDelete: WalletKey?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: Metric.gutter) {
                header
                if store.keys.isEmpty {
                    emptyState
                } else {
                    ForEach(store.keys) { key in
                        KeyRow(key: key,
                               isActive: store.activeKeyID == key.id,
                               onUse: { store.activeKeyID = key.id },
                               onDelete: { toDelete = key })
                    }
                }
                if let err = errorMessage {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(Brand.danger)
                }
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
        .sheet(isPresented: $showNew) { NewEnclaveKeySheet(error: $errorMessage) }
        .sheet(isPresented: $showImport) { ImportKeySheet(error: $errorMessage) }
        .sheet(item: $toDelete) { key in DeleteKeySheet(key: key) }
        .onChange(of: model.requestImportKey) { _, want in
            if want { showImport = true; model.requestImportKey = false }
        }
        .onAppear {
            if model.requestImportKey { showImport = true; model.requestImportKey = false }
        }
    }

    private var header: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                PrimaryButton(title: "New Secure Enclave Key", systemImage: "touchid") {
                    if Biometrics.isAvailable || EnclaveSigner.isAvailable { showNew = true }
                    else { errorMessage = "Secure Enclave unavailable on this Mac" }
                }
                Button { showImport = true } label: {
                    Label("Import Key", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.glass).controlSize(.large)
            }
        }
    }

    private var emptyState: some View {
        GlassCard {
            VStack(spacing: 10) {
                Image(systemName: "key.horizontal")
                    .font(.system(size: 34)).foregroundStyle(Brand.brandGradient)
                Text("No keys yet").font(.headline)
                Text("Create a hardware-backed key in the Secure Enclave, or import an existing PulseVM key.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }
}

private struct KeyRow: View {
    let key: WalletKey
    let isActive: Bool
    var onUse: () -> Void
    var onDelete: () -> Void
    @State private var copied = false

    var body: some View {
        GlassCard(padding: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle().fill((key.isHardwareBacked ? Brand.accent : Brand.glow).opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: key.isHardwareBacked ? "touchid" : "key.fill")
                        .foregroundStyle(key.isHardwareBacked ? Brand.accent : Brand.glow)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(key.label).font(.body.weight(.semibold))
                        badge(key.isHardwareBacked ? "Secure Enclave" : "Imported",
                              tint: key.isHardwareBacked ? Brand.accent : Brand.glow)
                        badge(key.curve.rawValue.uppercased(), tint: .gray)
                        if isActive { badge("Active", tint: Brand.success) }
                    }
                    Text(key.pubKey)
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                        .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Menu {
                    Button("Copy public key") { copyPub() }
                    if !isActive { Button("Set as active") { onUse() } }
                    Divider()
                    Button("Delete…", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tint.opacity(0.18), in: .capsule)
            .foregroundStyle(tint)
    }

    private func copyPub() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(key.pubKey, forType: .string)
        copied = true
    }
}

// MARK: - New Enclave key

private struct NewEnclaveKeySheet: View {
    @Environment(KeyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var error: String?
    @State private var label = ""

    var body: some View {
        VStack(spacing: 18) {
            sheetHeader("Create Secure Enclave Key", systemImage: "touchid",
                        subtitle: "A new P-256 key is generated inside this Mac's Secure Enclave. The private key never leaves the chip; signing requires Touch ID.")
            TextField("Label (e.g. Treasury signer)", text: $label)
                .textFieldStyle(.roundedBorder)
            Spacer()
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.glass).controlSize(.large)
                PrimaryButton(title: "Create", systemImage: "plus") {
                    do { try store.createEnclaveKey(label: label); dismiss() }
                    catch { self.error = error.localizedDescription; dismiss() }
                }
            }
        }
        .padding(24).frame(width: 420, height: 320)
        .background(Brand.navy.gradient.opacity(0.5))
    }
}

// MARK: - Import key

private struct ImportKeySheet: View {
    @Environment(KeyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var error: String?
    @State private var label = ""
    @State private var secret = ""
    @State private var curve: WalletKey.Curve = .r1
    @State private var localError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sheetHeader("Import Key", systemImage: "square.and.arrow.down",
                        subtitle: "Paste a PVT_R1_…/PVT_K1_… key (or WIF / 64-char hex). It is stored in the Keychain behind Touch ID and never displayed again.")
            TextField("Label", text: $label).textFieldStyle(.roundedBorder)
            SecureField("PVT_R1_… / PVT_K1_… / WIF / hex", text: $secret)
                .textFieldStyle(.roundedBorder).font(.callout.monospaced())
                .onChange(of: secret) { _, new in curve = KeyStore.detectCurve(new) }
            Picker("Curve", selection: $curve) {
                Text("R1 (secp256r1)").tag(WalletKey.Curve.r1)
                Text("K1 (secp256k1)").tag(WalletKey.Curve.k1)
            }
            .pickerStyle(.segmented)
            if let e = localError {
                Label(e, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(Brand.danger)
            }
            Spacer()
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.glass).controlSize(.large)
                Spacer()
                PrimaryButton(title: "Import", systemImage: "checkmark") { runImport() }
                    .frame(width: 160)
                    .disabled(secret.isEmpty)
            }
        }
        .padding(24).frame(width: 460, height: 400)
        .background(Brand.navy.gradient.opacity(0.5))
    }

    private func runImport() {
        do {
            try store.importKey(secret: secret, label: label, curve: curve)
            secret = ""
            dismiss()
        } catch {
            localError = error.localizedDescription
        }
    }
}

// MARK: - Delete (Touch ID + typed DELETE)

private struct DeleteKeySheet: View {
    @Environment(KeyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let key: WalletKey
    @State private var confirmText = ""
    @State private var working = false
    @State private var failed: String?

    private var canDelete: Bool { confirmText == "DELETE" && !working }

    var body: some View {
        VStack(spacing: 16) {
            sheetHeader("Delete key", systemImage: "trash",
                        subtitle: "This permanently removes “\(key.label)”. \(key.isHardwareBacked ? "The Secure Enclave key will be destroyed and cannot be recovered." : "The imported key will be erased from the Keychain.") Make sure you have a backup if this key controls funds.")
            GlassCard(padding: 14) {
                Text(key.pubKey).font(.caption.monospaced())
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Type DELETE to confirm").font(.caption).foregroundStyle(.secondary)
                TextField("DELETE", text: $confirmText)
                    .textFieldStyle(.roundedBorder).font(.body.monospaced())
            }
            if let failed {
                Label(failed, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(Brand.danger)
            }
            Spacer()
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.glass).controlSize(.large)
                Spacer()
                Button(role: .destructive) { confirmDelete() } label: {
                    Label(working ? "Authenticating…" : "Delete key", systemImage: "trash")
                        .frame(width: 150).padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent).tint(Brand.danger)
                .controlSize(.large)
                .disabled(!canDelete)
            }
        }
        .padding(24).frame(width: 460, height: 400)
        .background(Brand.navy.gradient.opacity(0.5))
    }

    private func confirmDelete() {
        working = true
        Task {
            let ok = await Biometrics.authenticate(reason: "Delete key “\(key.label)”")
            working = false
            if ok {
                store.delete(key)
                dismiss()
            } else {
                failed = "Authentication failed or cancelled."
            }
        }
    }
}

// Shared sheet header.
private func sheetHeader(_ title: String, systemImage: String, subtitle: String) -> some View {
    VStack(spacing: 10) {
        Image(systemName: systemImage)
            .font(.system(size: 38)).foregroundStyle(Brand.brandGradient)
        Text(title).font(.title2.weight(.semibold))
        Text(subtitle).font(.callout).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}
