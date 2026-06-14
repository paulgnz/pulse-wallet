import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(KeyStore.self) private var keyStore

    @State private var showStake = false

    /// A held key whose public key is in the account's active permission.
    private var controllingKey: WalletKey? {
        guard let perms = model.account?.permissions else { return nil }
        let activeKeys = Set(perms
            .filter { $0.permName == model.permissionName }
            .flatMap { $0.requiredAuth.keys.map(\.key) })
        return keyStore.keys.first { activeKeys.contains($0.pubKey) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Metric.gutter) {
                balanceHero
                if model.account != nil { SetupHealthBanner() }
                quickActions
                if model.account != nil { resources }
                holdings
                recentActivity
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
        .sheet(isPresented: $showStake) { StakeSheet() }
    }

    // MARK: Hero balance
    private var balanceHero: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Total balance").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    if let key = controllingKey {
                        Label(key.isHardwareBacked ? "Secure Enclave" : "Signed in",
                              systemImage: key.isHardwareBacked ? "touchid" : "key.fill")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .glassEffect(.regular, in: .capsule)
                            .foregroundStyle(Brand.accent)
                    } else {
                        Label("Watch-only", systemImage: "eye")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .glassEffect(.regular, in: .capsule)
                            .foregroundStyle(.secondary)
                    }
                    if model.isLoading { ProgressView().controlSize(.small) }
                }
                if let err = model.loadError {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(Brand.warn)
                } else {
                    Text(heroBalance)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Brand.brandGradient)
                        .contentTransition(.numericText())
                    Text("\(model.accountName) @ \(model.permissionName)")
                        .font(.callout.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var heroBalance: String {
        if let a = model.primaryAsset { return a.formatted }
        return model.isLoading ? "…" : "—"
    }

    // Shown when no held key controls this account.
    private var watchOnlyBanner: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: "eye").foregroundStyle(Brand.warn)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Watch-only account").font(.callout.weight(.medium))
                    Text("Add a key that controls \(model.accountName) to send and sign.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add key") { model.section = .keys; model.requestImportKey = true }
                    .buttonStyle(.glass)
            }
        }
    }

    // MARK: Quick actions
    private var quickActions: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                PrimaryButton(title: "Send", systemImage: "arrow.up.right") { model.section = .send }
                Button { model.section = .receive } label: {
                    Label("Receive", systemImage: "arrow.down.left")
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
        }
    }

    // MARK: Resources
    @ViewBuilder private var resources: some View {
        if let a = model.account {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: "Resources", systemImage: "gauge.with.dots.needle.33percent")
                    Button("Manage") { showStake = true }
                        .buttonStyle(.glass)
                }
                GlassCard(padding: 16) {
                    VStack(spacing: 14) {
                        ResourceBar(label: "CPU", fraction: a.cpuLimit.usedFraction, tint: Brand.accent,
                                    detail: a.cpuLimit.max < 0 ? "Unlimited" : nil)
                        ResourceBar(label: "NET", fraction: a.netLimit.usedFraction, tint: Brand.glow,
                                    detail: a.netLimit.max < 0 ? "Unlimited" : nil)
                        ResourceBar(label: "RAM", fraction: a.ramFraction, tint: Brand.success,
                                    detail: a.ramQuota < 0 ? "Unlimited" : "\(a.ramUsage) / \(a.ramQuota) B")
                    }
                }
            }
        }
    }

    // MARK: Holdings
    private var holdings: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Assets", systemImage: "circle.grid.2x2")
            if model.assets.isEmpty {
                GlassCard(padding: 14) {
                    Text(model.isLoading ? "Loading balances…" : "No balances")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            ForEach(model.assets) { asset in
                GlassCard(padding: 14) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Brand.primary.opacity(0.18)).frame(width: 38, height: 38)
                            Text(String(asset.symbol.prefix(1)))
                                .font(.headline).foregroundStyle(Brand.accent)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(asset.symbol).font(.body.weight(.semibold))
                                if asset.role == .resource {
                                    Text("RESOURCE")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Brand.glow.opacity(0.18), in: .capsule)
                                        .foregroundStyle(Brand.glow)
                                }
                            }
                            Text(asset.contract).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(asset.formatted).font(.body.monospacedDigit())
                    }
                }
            }
        }
    }

    // MARK: Recent activity preview
    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Recent", systemImage: "clock")
            if model.activity.isEmpty {
                GlassCard(padding: 14) {
                    Text("No recent activity yet — history arrives with Hyperion indexing.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                ForEach(model.activity.prefix(3)) { item in ActivityRow(item: item) }
                Button("View all activity") { model.section = .activity }
                    .buttonStyle(.link)
            }
        }
    }
}
