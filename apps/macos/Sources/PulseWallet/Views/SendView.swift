import SwiftUI

struct SendView: View {
    @Environment(AppModel.self) private var model

    @State private var recipient = ""
    @State private var amount = ""
    @State private var symbol = "SYS"
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
    @Environment(\.dismiss) private var dismiss
    let recipient: String
    let amount: String
    let symbol: String
    let memo: String

    @State private var state: SignState = .review
    enum SignState { case review, signing, broadcast, done, failed(String) }

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
            Spacer()
            actions
        }
        .padding(24)
        .frame(width: 420, height: 440)
        .background(Brand.navy.gradient.opacity(0.5))
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
        case .done:
            PrimaryButton(title: "Done", systemImage: "checkmark") { dismiss() }
        case .failed(let msg):
            VStack(spacing: 10) {
                Text(msg).font(.caption).foregroundStyle(Brand.danger)
                Button("Close") { dismiss() }.buttonStyle(.glass)
            }
        default:
            ProgressView().controlSize(.large)
        }
    }

    private func sign() {
        // Wires to EnclaveSigner -> pulse-wallet-core (assemble_sig_r1) -> RPC push.
        // Flow scaffolded; live broadcast lands with the uniffi binding.
        state = .signing
    }

    private var isWorking: Bool {
        if case .review = state { return false }
        if case .done = state { return false }
        if case .failed = state { return false }
        return true
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v).fontWeight(.medium) }
    }

    private var stateIcon: String {
        switch state {
        case .review:    return "signature"
        case .signing:   return "touchid"
        case .broadcast: return "antenna.radiowaves.left.and.right"
        case .done:      return "checkmark.seal.fill"
        case .failed:    return "xmark.seal.fill"
        }
    }
    private var stateTitle: String {
        switch state {
        case .review:    return "Confirm transfer"
        case .signing:   return "Authenticate"
        case .broadcast: return "Broadcasting…"
        case .done:      return "Sent"
        case .failed:    return "Failed"
        }
    }
}
