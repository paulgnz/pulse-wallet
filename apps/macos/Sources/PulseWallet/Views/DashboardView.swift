import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: Metric.gutter) {
                balanceHero
                quickActions
                if model.account != nil { resources }
                holdings
                recentActivity
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: Hero balance
    private var balanceHero: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Total balance").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    if model.selectedAccount?.isHardwareBacked == true {
                        Label("Secure Enclave", systemImage: "touchid")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .glassEffect(.regular, in: .capsule)
                            .foregroundStyle(Brand.accent)
                    } else if model.isLoading {
                        ProgressView().controlSize(.small)
                    }
                }
                if let err = model.loadError {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(Brand.warn)
                } else {
                    Text(heroBalance)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.brandGradient)
                        .contentTransition(.numericText())
                    Text("\(model.accountName) @ \(model.permissionName)")
                        .font(.callout.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var heroBalance: String {
        if let a = model.assets.first { return a.formatted }
        if let s = model.coreSymbol { return "0.0000 \(s)" }
        return model.isLoading ? "…" : "—"
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
                SectionHeader(title: "Resources", systemImage: "gauge.with.dots.needle.33percent")
                GlassCard(padding: 16) {
                    VStack(spacing: 14) {
                        ResourceBar(label: "CPU", fraction: a.cpuLimit.usedFraction, tint: Brand.accent)
                        ResourceBar(label: "NET", fraction: a.netLimit.usedFraction, tint: Brand.glow)
                        ResourceBar(label: "RAM", fraction: a.ramFraction, tint: Brand.success,
                                    detail: "\(a.ramUsage) / \(a.ramQuota) B")
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
