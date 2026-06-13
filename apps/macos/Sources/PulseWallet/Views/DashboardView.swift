import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    private var primary: Asset? { model.assets.first }

    var body: some View {
        ScrollView {
            VStack(spacing: Metric.gutter) {
                balanceHero
                quickActions
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
                    }
                }
                Text(primary?.formatted ?? "—")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.brandGradient)
                    .contentTransition(.numericText())
                Text(model.selectedAccount.map { "\($0.name) @ \($0.permission)" } ?? "")
                    .font(.callout.monospaced()).foregroundStyle(.secondary)
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

    // MARK: Holdings
    private var holdings: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Assets", systemImage: "circle.grid.2x2")
            ForEach(model.assets) { asset in
                GlassCard(padding: 14) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Brand.primary.opacity(0.18)).frame(width: 38, height: 38)
                            Text(String(asset.symbol.prefix(1)))
                                .font(.headline).foregroundStyle(Brand.accent)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(asset.symbol).font(.body.weight(.semibold))
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
            ForEach(model.activity.prefix(3)) { item in ActivityRow(item: item) }
            Button("View all activity") { model.section = .activity }
                .buttonStyle(.link)
        }
    }
}
