import SwiftUI
import AppKit

/// Reveal an imported key's private key for backup. Gated by typed REVEAL +
/// Touch ID (prompted by the Keychain when the secret is read).
struct ExportKeySheet: View {
    @Environment(KeyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let key: WalletKey

    @State private var confirm = ""
    @State private var revealed: String?
    @State private var failed: String?
    @State private var working = false

    private var canReveal: Bool { confirm == "REVEAL" && !working }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: revealed == nil ? "eye.trianglebadge.exclamationmark" : "key.fill")
                    .font(.system(size: 38)).foregroundStyle(Brand.brandGradient)
                Text("Export “\(key.label)”").font(.title2.weight(.semibold))
                Text("Your private key controls funds. Anyone who sees it can spend. Store it somewhere safe and never share it.")
                    .font(.caption).foregroundStyle(Brand.warn).multilineTextAlignment(.center)
            }

            if let revealed {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(key.curve == .r1 ? "PVT_R1 private key" : "PVT_K1 private key")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(revealed).font(.caption.monospaced()).textSelection(.enabled).lineLimit(3)
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(revealed, forType: .string)
                        }.buttonStyle(.glass)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Type REVEAL and authenticate to show the key")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("REVEAL", text: $confirm)
                        .pulseField(mono: true)
                }
            }
            if let failed { Text(failed).font(.caption).foregroundStyle(Brand.danger) }
            Spacer()
            HStack {
                Button(revealed == nil ? "Cancel" : "Done") { dismiss() }
                    .buttonStyle(.glass).controlSize(.large)
                if revealed == nil {
                    Spacer()
                    Button(role: .destructive) { reveal() } label: {
                        Label(working ? "Authenticating…" : "Reveal", systemImage: "touchid")
                            .frame(width: 150).padding(.vertical, 4)
                    }
                    .buttonStyle(.glassProminent).tint(Brand.warn).controlSize(.large)
                    .disabled(!canReveal)
                }
            }
        }
        .padding(24).frame(width: 460, height: 400)
        .background(BrandBackground())
    }

    private func reveal() {
        working = true
        Task {
            do {
                revealed = try await store.exportSecret(key, reason: "Export “\(key.label)” private key")
            } catch {
                failed = error.localizedDescription
            }
            working = false
        }
    }
}
