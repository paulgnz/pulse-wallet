import SwiftUI

/// Guided first-run: intro → choose account → add/confirm a key → review setup.
/// Account-aware throughout — it loads the account, checks whether you hold a key
/// that controls it, and recommends a safe setup before you start.
struct WelcomeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(KeyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    enum Step: Int { case intro, account, key, review }
    @State private var step: Step = .intro
    @State private var accountField = ""
    @State private var working = false
    @State private var note: String?

    private var controlsAccount: Bool {
        guard model.account != nil else { return false }
        return store.keys.contains { model.keyControlsAccount($0.pubKey) }
    }

    var body: some View {
        VStack(spacing: 18) {
            switch step {
            case .intro:   intro
            case .account: accountStep
            case .key:     keyStep
            case .review:  reviewStep
            }
        }
        .padding(28).frame(width: 460, height: 580)
        .background(BrandBackground())
        .onAppear { if accountField.isEmpty { accountField = model.accountName } }
    }

    // MARK: Intro
    private var intro: some View {
        VStack(spacing: 18) {
            brandMark
            Text("Welcome to PulseVM").font(.title.weight(.bold))
            Text("The native macOS wallet for PulseVM. Keys live in this Mac's Secure Enclave (or a YubiKey) and sign with Touch ID — they never leave the hardware.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    bullet("eye", "Watch any account", "View balances, resources, and history — no key needed.")
                    Divider()
                    bullet("touchid", "Hold a hardware key", "Create a Secure Enclave key, or import an R1/K1 key, to sign.")
                    Divider()
                    bullet("checkmark.shield", "Guided & safe", "We'll check your account setup and recommend a safe key layout.")
                }
            }
            Spacer()
            PrimaryButton(title: "Get started", systemImage: "arrow.right") { step = .account }
            Button("Just explore") { finish() }.buttonStyle(.glass).controlSize(.large)
        }
    }

    // MARK: Account
    private var accountStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader("Choose your account", "Enter the PulseVM account you want to use. We'll load it to see how it's set up. You can change this later.")
            HStack {
                TextField("account name", text: $accountField).pulseField(mono: true)
                PrimaryButton(title: working ? "Loading…" : "Load", systemImage: "arrow.down.circle") { loadAccount() }
                    .frame(width: 120).disabled(working || accountField.isEmpty)
            }
            if let note { Text(.init(note)).font(.caption).foregroundStyle(.secondary) }
            if model.account != nil {
                GlassCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Found \(model.accountName)", systemImage: "checkmark.seal.fill")
                            .font(.callout.weight(.medium)).foregroundStyle(Brand.success)
                        Text(controlsAccount
                             ? "This wallet already holds a key that controls it."
                             : "You don't hold a key for it yet — next step adds one.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            HStack {
                Button("Back") { step = .intro }.buttonStyle(.glass).controlSize(.large)
                Spacer()
                PrimaryButton(title: "Continue", systemImage: "arrow.right") { step = .key }
                    .frame(width: 150).disabled(model.account == nil)
            }
        }
    }

    // MARK: Key
    private var keyStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader("Add a signing key", controlsAccount
                ? "You already control this account — you can skip ahead, or add another key."
                : "To send and sign, this wallet needs a key that controls \(model.accountName). Pick one:")
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    optionRow("touchid", "Create a Secure Enclave key",
                              "Best for most people — generated in this Mac's chip, signs with Touch ID.") {
                        PrimaryButton(title: working ? "Creating…" : "Create", systemImage: "plus") { createEnclave() }
                            .frame(width: 120).disabled(working)
                    }
                    Divider()
                    optionRow("square.and.arrow.down", "Import an existing key",
                              "Bring a PVT_R1_…/PVT_K1_… key that already controls the account.") {
                        Button("Import") { finish(); model.section = .keys; model.requestImportKey = true }
                            .buttonStyle(.glass).controlSize(.large).frame(width: 120)
                    }
                    Divider()
                    optionRow("key.radiowaves.forward", "Use a YubiKey",
                              "Hardware key on a separate device — strongest for an @owner key.") {
                        Button("Set up") { finish(); model.section = .keys }
                            .buttonStyle(.glass).controlSize(.large).frame(width: 120)
                    }
                }
            }
            if let note { Text(.init(note)).font(.caption).foregroundStyle(Brand.accent) }
            Spacer()
            HStack {
                Button("Back") { step = .account }.buttonStyle(.glass).controlSize(.large)
                Spacer()
                PrimaryButton(title: "Continue", systemImage: "arrow.right") { step = .review }.frame(width: 150)
            }
        }
    }

    // MARK: Review
    private var reviewStep: some View {
        let issues = evaluateAccountHealth(account: model.account, accountName: model.accountName,
                                           keys: store.keys, unreadable: store.unreadableKeyIDs)
        return VStack(alignment: .leading, spacing: 14) {
            stepHeader("Your setup", "Here's how \(model.accountName) looks. The wallet will keep guiding you from the Keys page.")
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    if issues.isEmpty {
                        Label("Watching \(model.accountName) (no key held yet).", systemImage: "eye")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(issues.prefix(3)) { issue in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: issue.severity.icon).foregroundStyle(issue.severity.tint)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(issue.title).font(.callout.weight(.medium))
                                Text(issue.detail).font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            if !controlsAccount, store.keys.contains(where: { model.permissions(forKey: $0.pubKey).isEmpty }) {
                Text("Tip: you created a key but it isn't linked to \(model.accountName) yet. Open Keys → “Link to account” to add it.")
                    .font(.caption).foregroundStyle(Brand.warn)
            }
            Spacer()
            HStack {
                Button("Back") { step = .key }.buttonStyle(.glass).controlSize(.large)
                Spacer()
                PrimaryButton(title: "Open wallet", systemImage: "checkmark") { finish(); model.section = .keys }
                    .frame(width: 170)
            }
        }
    }

    // MARK: Actions
    private func loadAccount() {
        working = true; note = nil
        let name = accountField.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            model.addAccount(name)
            await model.refresh()
            working = false
            if model.account == nil {
                note = "Couldn't find **\(name)** on \(model.chainName). Check the name, or pick a different network in Settings."
            }
        }
    }

    private func createEnclave() {
        working = true; note = nil
        Task {
            do {
                let k = try store.createEnclaveKey(label: "Primary key")
                note = "Created ✓ — \(k.pubKey.prefix(16))…. \(controlsAccount ? "It controls your account." : "Next: link it to \(model.accountName) so it can sign.")"
            } catch { note = error.localizedDescription }
            working = false
        }
    }

    // MARK: Bits
    private var brandMark: some View {
        ZStack {
            Circle().fill(Brand.brandGradient).frame(width: 72, height: 72)
                .shadow(color: Brand.accent.opacity(0.5), radius: 18)
            Image(systemName: "bolt.fill").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
        }
    }
    private func stepHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.weight(.bold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
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
    private func optionRow(_ icon: String, _ title: String, _ body: String,
                           @ViewBuilder _ action: () -> some View) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon).foregroundStyle(Brand.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.semibold))
                Text(body).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            action()
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "wallet.didOnboard")
        dismiss()
    }
}
