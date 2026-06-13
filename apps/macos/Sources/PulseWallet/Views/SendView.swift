import SwiftUI

struct SendView: View {
    @Environment(AppModel.self) private var model

    @State private var recipient = ""
    @State private var amount = ""
    @State private var symbol = ""
    @State private var memo = ""
    @State private var showingConfirm = false

    private var canSend: Bool {
        !recipient.isEmpty && (Double(amount) ?? 0) > 0
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

                        field("Memo (optional)") {
                            TextField("reference", text: $memo)
                                .textFieldStyle(.plain)
                        }
                    }
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
    enum SignState { case review, signing, signed, broadcasting, sent(String), failed(String) }

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
                PrimaryButton(title: "Sign with Touch ID", systemImage: "touchid") { sign() }
            }
        case .signed:
            HStack {
                Button("Close") { dismiss() }
                    .buttonStyle(.glass).controlSize(.large)
                PrimaryButton(title: "Broadcast", systemImage: "antenna.radiowaves.left.and.right") { broadcast() }
            }
        case .sent(let txid):
            HStack {
                if let url = model.explorerTxURL(txid) {
                    Button { openURL(url) } label: { Label("Explorer", systemImage: "arrow.up.right.square") }
                        .buttonStyle(.glass).controlSize(.large)
                }
                PrimaryButton(title: "Done", systemImage: "checkmark") { dismiss() }
            }
        case .failed(let msg):
            VStack(spacing: 10) {
                Text(msg).font(.caption).foregroundStyle(Brand.danger)
                    .multilineTextAlignment(.center)
                Button("Close") { dismiss() }.buttonStyle(.glass)
            }
        default:
            ProgressView().controlSize(.large)
        }
    }

    private func sign() {
        guard let draft = model.makeTransferDraft(to: recipient, amount: amount, symbol: symbol, memo: memo) else {
            state = .failed("Couldn't build the transfer — not connected, or unknown token.")
            return
        }
        state = .signing
        let core = model.core
        let reason = "Sign transfer of \(draft.quantity) to \(draft.to)"
        Task {
            do {
                // Serialize the real Antelope transaction in the core, then sign its
                // digest with the active key (Enclave R1 / imported R1 / imported K1).
                let built = try core.buildTransfer(
                    from: draft.from, to: draft.to, quantity: draft.quantity, memo: draft.memo,
                    contract: draft.contract, actor: draft.actor, permission: draft.permission,
                    chainId: draft.chainId, refBlockNum: draft.refBlockNum,
                    refBlockPrefix: draft.refBlockPrefix, expiration: draft.expiration)
                guard let preImage = Data(hexString: built.preimage) else {
                    state = .failed("Malformed signing pre-image."); return
                }
                let sig = try await keyStore.sign(preImage: preImage, reason: reason)
                packedTrx = built.packed
                sigR1 = sig
                state = .signed
            } catch {
                state = .failed(error.localizedDescription)
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
                state = .failed(error.localizedDescription)
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
                Text("Real signature over the serialized transaction. Tap Broadcast to submit.")
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
        case .failed:       return "xmark.seal.fill"
        }
    }
    private var stateTitle: String {
        switch state {
        case .review:       return "Confirm transfer"
        case .signing:      return "Authenticate"
        case .signed:       return "Signed"
        case .broadcasting: return "Broadcasting…"
        case .sent:         return "Sent"
        case .failed:       return "Failed"
        }
    }
}
