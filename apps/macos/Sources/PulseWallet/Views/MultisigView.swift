import SwiftUI

struct MultisigView: View {
    @Environment(AppModel.self) private var model
    @Environment(KeyStore.self) private var keyStore

    @State private var proposals: [String] = []
    @State private var statuses: [AppModel.ProposalStatus] = []
    @State private var loading = false
    @State private var status: String?
    @State private var showPropose = false
    @State private var approveProposer = ""
    @State private var approveName = ""

    var body: some View {
        ScrollView {
            VStack(spacing: Metric.gutter) {
                header
                myProposals
                approveOther
                if let s = status {
                    GlassCard(padding: 12) {
                        Text(s).font(.caption).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
        .task(id: model.accountName) { await load() }
        .sheet(isPresented: $showPropose) { ProposeSheet(onDone: { Task { await load() } }) }
    }

    private var header: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                PrimaryButton(title: "New Proposal", systemImage: "plus") { showPropose = true }
                Button { Task { await load() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.glass).controlSize(.large)
            }
        }
    }

    private var myProposals: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Proposals by \(model.accountName)", systemImage: "tray.full")
            if loading {
                GlassCard(padding: 14) { ProgressView() }
            } else if proposals.isEmpty {
                GlassCard(padding: 14) {
                    Text("No open proposals.").font(.callout).foregroundStyle(.secondary)
                }
            } else {
                ForEach(proposals, id: \.self) { name in
                    GlassCard(padding: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "doc.badge.gearshape").foregroundStyle(Brand.accent)
                                Text(name).font(.body.monospaced().weight(.medium))
                                Spacer()
                                Button("Approve") { approve(proposer: model.accountName, name: name) }
                                    .buttonStyle(.glass)
                                Button("Execute") { exec(proposer: model.accountName, name: name) }
                                    .buttonStyle(.glassProminent).tint(Brand.primary)
                            }
                            if let st = statuses.first(where: { $0.name == name }) {
                                approvalStatus(st)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Approvals inbox row: who approved, who's still pending.
    private func approvalStatus(_ st: AppModel.ProposalStatus) -> some View {
        let total = st.provided.count + st.requested.count
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal").font(.caption2).foregroundStyle(Brand.success)
                Text("\(st.provided.count) / \(total) approvals").font(.caption.weight(.medium))
            }
            if !st.provided.isEmpty {
                Text("Approved: \(st.provided.joined(separator: ", "))")
                    .font(.caption2).foregroundStyle(Brand.success).lineLimit(1).truncationMode(.tail)
            }
            if !st.requested.isEmpty {
                Text("Pending: \(st.requested.joined(separator: ", "))")
                    .font(.caption2).foregroundStyle(Brand.warn).lineLimit(1).truncationMode(.tail)
            }
        }
    }

    private var approveOther: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Approve a proposal", systemImage: "checkmark.seal")
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Proposer account", text: $approveProposer)
                        .pulseField(mono: true)
                    TextField("Proposal name", text: $approveName)
                        .pulseField(mono: true)
                    Button("Approve as \(model.accountName)") {
                        approve(proposer: approveProposer, name: approveName)
                    }
                    .buttonStyle(.glass)
                    .disabled(approveProposer.isEmpty || approveName.isEmpty)
                }
            }
        }
    }

    private func load() async {
        loading = true
        async let p = model.proposals(by: model.accountName)
        async let s = model.proposalStatuses(by: model.accountName)
        proposals = await p
        statuses = await s
        loading = false
    }

    // MARK: actions

    private func approve(proposer: String, name: String) {
        guard let ctx = model.taposContext() else { status = "Not connected."; return }
        let me = model.accountName, perm = model.permissionName
        Task {
            do {
                let tx = try model.core.msigApprove(
                    contract: model.msigContract, proposer: proposer, proposal: name,
                    levelActor: me, levelPerm: perm, authActor: me, authPerm: perm,
                    chainId: ctx.chainId, refBlockNum: ctx.refBlockNum,
                    refBlockPrefix: ctx.refBlockPrefix, expiration: ctx.expiration)
                try await submit(tx, reason: "Approve \(proposer)/\(name)")
            } catch { status = error.localizedDescription }
        }
    }

    private func exec(proposer: String, name: String) {
        guard let ctx = model.taposContext() else { status = "Not connected."; return }
        let me = model.accountName
        Task {
            do {
                let tx = try model.core.msigExec(
                    contract: model.msigContract, proposer: proposer, proposal: name, executer: me,
                    chainId: ctx.chainId, refBlockNum: ctx.refBlockNum,
                    refBlockPrefix: ctx.refBlockPrefix, expiration: ctx.expiration)
                try await submit(tx, reason: "Execute \(proposer)/\(name)")
            } catch { status = error.localizedDescription }
        }
    }

    private func submit(_ tx: BuiltTx, reason: String) async throws {
        guard model.keyControlsAccount(keyStore.activeKey?.pubKey) else {
            throw PulseCoreError.badInput("Your active key doesn't control \(model.accountName). Set a controlling key active in Keys.")
        }
        guard let preImage = Data(hexString: tx.preimage) else { return }
        let sig = try await keyStore.sign(preImage: preImage, reason: reason)
        let txid = try await model.broadcast(signatures: [sig], packedTrx: tx.packed)
        status = "Submitted: \(txid)"
        await load()
    }
}

/// Propose a transfer that requires approvals.
private struct ProposeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(KeyStore.self) private var keyStore
    @Environment(\.dismiss) private var dismiss
    var onDone: () -> Void

    @State private var proposalName = ""
    @State private var requested = ""
    @State private var to = ""
    @State private var amount = ""
    @State private var symbol = ""
    @State private var memo = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Proposal").font(.title2.weight(.semibold))
            Text("Propose a transfer that the requested accounts must approve before it can execute.")
                .font(.caption).foregroundStyle(.secondary)
            group("Proposal name (≤12 chars)") { TextField("e.g. pay1", text: $proposalName) }
            group("Requested approvers") { TextField("alice@active; bob@active", text: $requested) }
            group("To") { TextField("recipient", text: $to) }
            HStack {
                group("Amount") { TextField("0.0000", text: $amount) }
                group("Token") {
                    Picker("", selection: $symbol) {
                        if symbol.isEmpty || !model.assets.contains(where: { $0.symbol == symbol }) {
                            Text("—").tag("")
                        }
                        ForEach(model.assets) { Text($0.symbol).tag($0.symbol) }
                    }.labelsHidden()
                }.fixedSize()
            }
            group("Memo") { TextField("optional", text: $memo) }
            if let error { Text(error).font(.caption).foregroundStyle(Brand.danger) }
            Spacer()
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.glass).controlSize(.large)
                Spacer()
                PrimaryButton(title: working ? "Working…" : "Propose & Sign", systemImage: "paperplane") { propose() }
                    .frame(width: 200)
                    .disabled(working || proposalName.isEmpty || requested.isEmpty || to.isEmpty || amount.isEmpty)
            }
        }
        .padding(24).frame(width: 460, height: 540)
        .background(BrandBackground())
        .onAppear { if symbol.isEmpty { symbol = model.primaryAsset?.symbol ?? "" } }
    }

    private func group(_ label: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            content().pulseField(mono: true)
        }
    }

    private func propose() {
        guard model.keyControlsAccount(keyStore.activeKey?.pubKey) else {
            error = "Your active key doesn't control \(model.accountName). Set a controlling key active in Keys."
            return
        }
        guard let ctx = model.taposContext(),
              let asset = model.assets.first(where: { $0.symbol == symbol }),
              let qty = AppModel.formatQuantity(amount, precision: asset.precision, symbol: symbol) else {
            error = "Not connected or invalid amount."; return
        }
        working = true
        let me = model.accountName
        Task {
            do {
                let tx = try model.core.msigProposeTransfer(
                    contract: model.msigContract, proposer: me, proposal: proposalName,
                    requested: requested, from: me, to: to, quantity: qty, memo: memo,
                    tokenContract: asset.contract, innerExpiration: ctx.expiration,
                    chainId: ctx.chainId, refBlockNum: ctx.refBlockNum,
                    refBlockPrefix: ctx.refBlockPrefix, expiration: ctx.expiration)
                guard let preImage = Data(hexString: tx.preimage) else { error = "bad preimage"; working = false; return }
                let sig = try await keyStore.sign(preImage: preImage, reason: "Propose \(proposalName)")
                _ = try await model.broadcast(signatures: [sig], packedTrx: tx.packed)
                working = false
                onDone()
                dismiss()
            } catch {
                self.error = error.localizedDescription
                working = false
            }
        }
    }
}
