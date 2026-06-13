import SwiftUI

/// First-run welcome — explains watch-only vs holding a key, and routes to setup.
struct WelcomeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Brand.brandGradient).frame(width: 72, height: 72)
                    .shadow(color: Brand.accent.opacity(0.5), radius: 18)
                Image(systemName: "bolt.fill").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
            }
            Text("Welcome to PulseVM").font(.title.weight(.bold))
            Text("The native macOS wallet for PulseVM. Keys live in this Mac's Secure Enclave and sign with Touch ID — they never leave the chip.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)

            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    bullet("eye", "Watch any account", "View balances, resources, and history — no key needed.")
                    Divider()
                    bullet("touchid", "Create a hardware key", "Generate a Secure Enclave (R1) key to sign and send.")
                    Divider()
                    bullet("square.and.arrow.down", "Import an existing key", "Bring an R1 or K1 key to control an existing account.")
                }
            }
            Spacer()
            VStack(spacing: 10) {
                PrimaryButton(title: "Create Secure Enclave Key", systemImage: "touchid") {
                    finish(); model.section = .keys
                }
                HStack {
                    Button("Import a key") { finish(); model.section = .keys; model.requestImportKey = true }
                        .buttonStyle(.glass).controlSize(.large)
                    Button("Just explore") { finish() }
                        .buttonStyle(.glass).controlSize(.large)
                }
            }
        }
        .padding(28).frame(width: 460, height: 560)
        .background(BrandBackground())
    }

    private func bullet(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(Brand.accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.semibold))
                Text(body).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "wallet.didOnboard")
        dismiss()
    }
}
