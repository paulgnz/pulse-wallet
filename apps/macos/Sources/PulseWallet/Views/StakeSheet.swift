import SwiftUI

/// Stake / unstake CPU·NET and claim refunds (pulse system contract, in SYS).
struct StakeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(KeyStore.self) private var keyStore
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable, Identifiable {
        case stake = "Stake", unstake = "Unstake", refund = "Refund"
        var id: String { rawValue }
    }
    @State private var mode: Mode = .stake
    @State private var receiver = ""
    @State private var cpu = "0"
    @State private var net = "0"
    @State private var working = false
    @State private var status: String?

    private var sym: String { model.coreSymbol ?? "SYS" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Resources").font(.title2.weight(.semibold))
            Text("Stake \(sym) for CPU/NET bandwidth, unstake it (refundable after the chain's unstaking period), or claim a matured refund.")
                .font(.caption).foregroundStyle(.secondary)

            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }.labelsHidden().pickerStyle(.segmented)

            if mode != .refund {
                field("Receiver (default: self)") {
                    TextField(model.accountName, text: $receiver).font(.callout.monospaced())
                }
                HStack {
                    field("CPU (\(sym))") { TextField("0.0000", text: $cpu).font(.callout.monospacedDigit()) }
                    field("NET (\(sym))") { TextField("0.0000", text: $net).font(.callout.monospacedDigit()) }
                }
            } else {
                Text("Claims any \(sym) whose unstaking period has elapsed back to your liquid balance.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            if let status {
                Text(status).font(.caption)
                    .foregroundStyle(status.hasPrefix("Submitted") ? Brand.success : Brand.danger)
                    .textSelection(.enabled)
            }
            Spacer()
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.glass).controlSize(.large)
                Spacer()
                PrimaryButton(title: working ? "Working…" : mode.rawValue, systemImage: icon) { submit() }
                    .frame(width: 170).disabled(working)
            }
        }
        .padding(24).frame(width: 460, height: 420)
        .background(BrandBackground())
        .onAppear { if receiver.isEmpty { receiver = model.accountName } }
    }

    private var icon: String {
        switch mode { case .stake: return "lock.shield"; case .unstake: return "lock.open"; case .refund: return "arrow.uturn.down" }
    }

    private func field(_ label: String, @ViewBuilder _ c: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            c().pulseField(mono: true)
        }
    }

    private func submit() {
        guard model.keyControlsAccount(keyStore.activeKey?.pubKey) else {
            status = "Your active key doesn't control \(model.accountName). Set a controlling key active in Keys."
            return
        }
        guard let ctx = model.taposContext() else { status = "Not connected."; return }
        let me = model.accountName
        let rcv = receiver.trimmingCharacters(in: .whitespaces).isEmpty ? me : receiver.trimmingCharacters(in: .whitespaces)
        guard let netQ = AppModel.formatQuantity(net, precision: 4, symbol: sym),
              let cpuQ = AppModel.formatQuantity(cpu, precision: 4, symbol: sym) else {
            status = "Invalid amount."; return
        }
        working = true
        Task {
            do {
                let tx: BuiltTx
                switch mode {
                case .stake:
                    tx = try model.core.buildStake(contract: "pulse", from: me, receiver: rcv,
                        netQty: netQ, cpuQty: cpuQ, transfer: false, chainId: ctx.chainId,
                        refBlockNum: ctx.refBlockNum, refBlockPrefix: ctx.refBlockPrefix, expiration: ctx.expiration)
                case .unstake:
                    tx = try model.core.buildUnstake(contract: "pulse", from: me, receiver: rcv,
                        netQty: netQ, cpuQty: cpuQ, chainId: ctx.chainId,
                        refBlockNum: ctx.refBlockNum, refBlockPrefix: ctx.refBlockPrefix, expiration: ctx.expiration)
                case .refund:
                    tx = try model.core.buildRefund(contract: "pulse", owner: me, chainId: ctx.chainId,
                        refBlockNum: ctx.refBlockNum, refBlockPrefix: ctx.refBlockPrefix, expiration: ctx.expiration)
                }
                guard let preImage = Data(hexString: tx.preimage) else { status = "bad preimage"; working = false; return }
                let sig = try await keyStore.sign(preImage: preImage, reason: "\(mode.rawValue) resources")
                let txid = try await model.broadcast(signatures: [sig], packedTrx: tx.packed)
                status = "Submitted: \(txid)"
                await model.refresh()
                working = false
            } catch {
                status = error.localizedDescription
                working = false
            }
        }
    }
}
