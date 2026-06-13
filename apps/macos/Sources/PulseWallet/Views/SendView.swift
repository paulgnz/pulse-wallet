import SwiftUI

struct SendView: View {
    @Environment(AppModel.self) private var model
    @Environment(KeyStore.self) private var keyStore

    @State private var recipient = ""
    @State private var amount = ""
    @State private var symbol = ""
    @State private var memo = ""
    @State private var showingConfirm = false

    /// A held key whose pubkey is in the account's active permission.
    private var canSign: Bool {
        guard let perms = model.account?.permissions else { return false }
        let active = Set(perms.first { $0.permName == model.permissionName }?
            .requiredAuth.keys.map(\.key) ?? [])
        return keyStore.keys.contains { active.contains($0.pubKey) }
    }
    /// Antelope account name: 1–12 chars of [.a-z1-5].
    private var recipientValid: Bool {
        let r = recipient.trimmingCharacters(in: .whitespaces)
        return !r.isEmpty && r.count <= 12 && r.allSatisfy { "abcdefghijklmnopqrstuvwxyz12345.".contains($0) }
    }
    private var amountValue: Decimal { Decimal(string: amount.trimmingCharacters(in: .whitespaces)) ?? 0 }
    private var balance: Decimal { model.assets.first { $0.symbol == symbol }?.amount ?? 0 }
    private var overBalance: Bool { amountValue > balance }

    private var validationError: String? {
        if !canSign { return "Watch-only account — add a key that controls \(model.accountName) to send." }
        if !recipient.isEmpty && !recipientValid { return "Invalid account name (use a–z, 1–5, '.', ≤12 chars)." }
        if amountValue > 0 && overBalance { return "Amount exceeds your \(symbol) balance (\(balance))." }
        return nil
    }
    private var canSend: Bool {
        canSign && recipientValid && amountValue > 0 && !overBalance && !symbol.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Metric.gutter) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "Transfer", systemImage: "paperplane")

                        field("To account") {
                            TextField("e.g. treasury.nz", text: $recipient)
                                .textFieldStyle(.plain)
                                .font(.body.monospaced())
                        }

                        field("Amount") {
                            HStack {
                                TextField("0.0000", text: $amount)
                                    .textFieldStyle(.plain)
                                    .font(.title3.monospacedDigit())
                                Button("Max") { amount = "\(NSDecimalNumber(decimal: balance))" }
                                    .buttonStyle(.link).font(.caption)
                                Picker("", selection: $symbol) {
                                    if symbol.isEmpty || !model.assets.contains(where: { $0.symbol == symbol }) {
                                        Text("—").tag("")
                                    }
                                    ForEach(model.assets) { Text($0.symbol).tag($0.symbol) }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .fixedSize()
                            }
                        }
                        Text("Available: \(NSDecimalNumber(decimal: balance)) \(symbol)")
                            .font(.caption2).foregroundStyle(.secondary)

                        field("Memo (optional)") {
                            TextField("reference", text: $memo)
                                .textFieldStyle(.plain)
                        }
                    }
                }

                if let err = validationError {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(Brand.warn)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                PrimaryButton(title: "Review & Sign", systemImage: "signature") {
                    showingConfirm = true
                }
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.5)
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
        .onAppear {
            if symbol.isEmpty { symbol = model.primaryAsset?.symbol ?? "" }
        }
        .sheet(isPresented: $showingConfirm) {
            SignSheet(recipient: recipient, amount: amount, symbol: symbol, memo: memo)
        }
    }

    @ViewBuilder
    private func field(_ label: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            content()
                .padding(12)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
        }
    }
}

/// Biometric signing confirmation — the moment Secure Enclave shines.
struct SignSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(KeyStore.self) private var keyStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let recipient: String
    let amount: String
    let symbol: String
    let memo: String

    @State private var state: SignState = .review
    @State private var sigR1: String?
    @State private var packedTrx: String?
    enum SignState { case review, signing, signed, broadcasting, sent(String), failed(WalletError) }

    var body: some View {
        VStack(spacing: 20) {
            header
            GlassCard {
                VStack(spacing: 14) {
                    row("From", model.selectedAccount?.name ?? "—")
                    Divider()
                    row("To", recipient)
                    Divider()
                    row("Amount", "\(amount) \(symbol)")
                    if !memo.isEmpty { Divider(); row("Memo", memo) }
                }
            }
            if case .sent(let txid) = state {
                sentCard(txid)
            } else if let sig = sigR1 {
                signatureCard(sig)
            }
            Spacer()
            actions
        }
        .padding(24)
        .frame(width: 420, height: 500)
        .background(BrandBackground())
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: stateIcon)
                .font(.system(size: 42))
                .foregroundStyle(Brand.brandGradient)
                .symbolEffect(.pulse, isActive: isWorking)
            Text(stateTitle).font(.title2.weight(.semibold))
        }
    }

    @ViewBuilder private var actions: some View {
        switch state {
        case .review:
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.glass).controlSize(.large)
                PrimaryButton(title: "Sign & Send", systemImage: "touchid") { sign() }
            }
        case .sent(let txid):
            HStack {
                if let url = model.explorerTxURL(txid) {
                    Button { openURL(url) } label: { Label("Explorer", systemImage: "arrow.up.right.square") }
                        .buttonStyle(.glass).controlSize(.large)
                }
                PrimaryButton(title: "Done", systemImage: "checkmark") { dismiss() }
            }
        case .failed(let e):
            VStack(spacing: 10) {
                VStack(spacing: 3) {
                    Text(e.title).font(.callout.weight(.semibold))
                        .foregroundStyle(e.severity == .warning ? Brand.warn : Brand.danger)
                    if !e.detail.isEmpty {
                        Text(e.detail).font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                HStack {
                    Button("Close") { dismiss() }.buttonStyle(.glass).controlSize(.large)
                    // If we already have a signature, retry just the broadcast (no re-sign).
                    if sigR1 != nil {
                        PrimaryButton(title: "Retry broadcast", systemImage: "arrow.clockwise") { broadcast() }
                    }
                }
            }
        default:
            ProgressView().controlSize(.large)
        }
    }

    /// Build → sign (Touch ID) → broadcast, in one step.
    private func sign() {
        guard let draft = model.makeTransferDraft(to: recipient, amount: amount, symbol: symbol, memo: memo) else {
            state = .failed(.error("Couldn't build the transfer", "Not connected, or unknown token."))
            return
        }
        state = .signing
        let core = model.core
        let reason = "Sign transfer of \(draft.quantity) to \(draft.to)"
        Task {
            do {
                let built = try core.buildTransfer(
                    from: draft.from, to: draft.to, quantity: draft.quantity, memo: draft.memo,
                    contract: draft.contract, actor: draft.actor, permission: draft.permission,
                    chainId: draft.chainId, refBlockNum: draft.refBlockNum,
                    refBlockPrefix: draft.refBlockPrefix, expiration: draft.expiration)
                guard let preImage = Data(hexString: built.preimage) else {
                    state = .failed(.error("Malformed signing pre-image.")); return
                }
                sigR1 = try await keyStore.sign(preImage: preImage, reason: reason)
                packedTrx = built.packed
                broadcast()   // ← sign and send in one flow
            } catch {
                state = .failed(FriendlyError.explain(error, paused: model.networkPaused, headBlock: model.chainInfo?.headBlockNum))
            }
        }
    }

    private func broadcast() {
        guard let sig = sigR1, let packed = packedTrx else { return }
        state = .broadcasting
        Task {
            do {
                let txid = try await model.broadcast(signatures: [sig], packedTrx: packed)
                state = .sent(txid)
                await model.refresh()
            } catch {
                state = .failed(FriendlyError.explain(error, paused: model.networkPaused, headBlock: model.chainInfo?.headBlockNum))
            }
        }
    }

    private func sentCard(_ txid: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Label("Broadcast", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.medium)).foregroundStyle(Brand.success)
                Text(txid).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled).lineLimit(2)
            }
        }
    }

    private func signatureCard(_ sig: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Label("Signed with \(keyStore.activeKey?.label ?? "active key")",
                      systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.medium)).foregroundStyle(Brand.success)
                Text(sig)
                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled).lineLimit(4)
                Text("Real signature over the serialized transaction — broadcasting…")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var isWorking: Bool {
        switch state {
        case .signing, .broadcasting: return true
        default: return false
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v).fontWeight(.medium) }
    }

    private var stateIcon: String {
        switch state {
        case .review:       return "signature"
        case .signing:      return "touchid"
        case .signed:       return "checkmark.seal.fill"
        case .broadcasting: return "antenna.radiowaves.left.and.right"
        case .sent:         return "paperplane.fill"
        case .failed(let e): return e.severity == .warning ? "clock.badge.checkmark" : "xmark.seal.fill"
        }
    }
    private var stateTitle: String {
        switch state {
        case .review:       return "Confirm transfer"
        case .signing:      return "Authenticate"
        case .signed:       return "Signed"
        case .broadcasting: return "Broadcasting…"
        case .sent:         return "Sent"
        case .failed(let e): return e.severity == .warning ? "Signed — waiting for the chain" : "Couldn't send"
        }
    }
}
