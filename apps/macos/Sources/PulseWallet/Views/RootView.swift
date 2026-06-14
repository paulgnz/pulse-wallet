import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(KeyStore.self) private var keyStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var showWelcome = !UserDefaults.standard.bool(forKey: "wallet.didOnboard")

    var body: some View {
        @Bindable var model = model

        NavigationSplitView(columnVisibility: $columnVisibility) {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            VStack(spacing: 0) {
                // Banner sits below the floating toolbar (not across the title bar),
                // so it never collides with the traffic lights / network pill.
                if model.signingWithOwner { OwnerWarningBanner() }
                detail
            }
            .navigationTitle(model.section.title)
            .toolbar {
                ToolbarItem(placement: .principal) { NetworkPill() }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await model.refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.isLoading)
                    .help("Refresh")
                }
                if !keyStore.keys.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button { model.lock() } label: { Image(systemName: "lock") }
                            .help("Lock wallet")
                    }
                }
            }
        }
        .background(BrandBackground())
        .tint(Brand.accent)   // selection highlight + controls follow the theme, not system blue
        .overlay {
            // Subtle red frame whenever signing is set to the high-privilege owner permission.
            if model.signingWithOwner {
                Rectangle().strokeBorder(Brand.danger.opacity(0.9), lineWidth: 2)
                    .ignoresSafeArea().allowsHitTesting(false)
            }
        }
        .animation(.smooth, value: model.signingWithOwner)
        .overlay { if model.isLocked { LockScreen() } }
        .animation(.smooth, value: model.isLocked)
        .task { await model.refresh() }
        .sheet(isPresented: $showWelcome) { WelcomeSheet() }
        .onAppear {
            // Lock at launch if there are keys to protect.
            if model.autoLock && !keyStore.keys.isEmpty { model.lock() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active && model.autoLock && !keyStore.keys.isEmpty { model.lock() }
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.section {
        case .wallet:   DashboardView()
        case .send:     SendView()
        case .receive:  ReceiveView()
        case .stablecoin:
            ComingSoonView(icon: "dollarsign.circle", title: "Stablecoin",
                blurb: "Hold, send, and redeem regulated stablecoins like Metal Dollar (USDM) directly in your PulseVM wallet.",
                bullets: ["Issue / redeem with the token issuer", "On-chain transfers with instant finality",
                          "Per-asset compliance controls (freeze, allow-lists)"])
        case .staking:
            ComingSoonView(icon: "chart.line.uptrend.xyaxis", title: "Staking",
                blurb: "Stake to earn and manage rewards. (CPU/NET resource staking is available now under Wallet → Resources → Manage.)",
                bullets: ["Yield/reward staking", "Auto-compounding", "Validator/delegation selection"])
        case .activity: ActivityView()
        case .multisig: MultisigView()
        case .keys:     KeysView()
        case .tools:    ToolsView()
        case .settings: SettingsView()
        }
    }
}

/// Persistent red bar shown while signing is set to the owner permission.
struct OwnerWarningBanner: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.shield.fill")
            Text("Signing as **owner** — the highest-privilege permission. Use **active** for everyday transactions.")
                .font(.callout)
            Spacer()
            Button("Switch to active") { model.permissionName = "active" }
                .buttonStyle(.borderless).font(.callout.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Brand.danger)
    }
}

/// Live network indicator in the toolbar — a custom popover (not a native Menu,
/// which adds its own chevron) so we control width and show connection status.
struct NetworkPill: View {
    @Environment(AppModel.self) private var model
    @State private var open = false

    private var paused: Bool { model.networkPaused }
    private var connecting: Bool { model.chainInfo == nil }
    private var dot: Color { connecting ? Brand.warn : (paused ? Brand.warn : Brand.success) }
    private var statusText: String { connecting ? "Connecting…" : (paused ? "Paused" : "Connected") }

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 7) {
                StatusDot(color: dot)
                Text(model.chainName).font(.callout.weight(.semibold))
                if paused { Text("paused").font(.caption.weight(.medium)).foregroundStyle(Brand.warn) }
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4).padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .popover(isPresented: $open, arrowEdge: .bottom) {
            NetworkPopover(open: $open)
                .frame(width: 340)
        }
    }
}

/// A glowing connection-status dot.
private struct StatusDot: View {
    let color: Color
    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7)
            .overlay(Circle().fill(color).blur(radius: 2.5).opacity(0.7))
    }
}

/// Wide network switcher: live status header for the active chain + the full
/// network list to switch between + manage.
private struct NetworkPopover: View {
    @Environment(AppModel.self) private var model
    @Binding var open: Bool

    private var paused: Bool { model.networkPaused }
    private var connecting: Bool { model.chainInfo == nil }
    private var dot: Color { connecting ? Brand.warn : (paused ? Brand.warn : Brand.success) }
    private var statusText: String { connecting ? "Connecting…" : (paused ? "Paused" : "Connected") }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Active-network status header
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    StatusDot(color: dot)
                    Text(statusText).font(.callout.weight(.semibold)).foregroundStyle(dot)
                    Spacer()
                    if let info = model.chainInfo {
                        Text("v\(info.serverVersion)").font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                if let info = model.chainInfo {
                    HStack(spacing: 14) {
                        Stat("Head block", "#\(info.headBlockNum.formatted())")
                        Stat("Account", model.accountName)
                    }
                }
                Text(model.networks.active.rpc)
                    .font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            .padding(14)
            .background(Brand.accent.opacity(0.08))

            Divider()

            // Switchable network list
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(model.networks.networks) { n in
                        let selected = n.id == model.networks.selectedID
                        Button {
                            if !selected { model.switchNetwork(n) }
                            open = false
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selected ? "checkmark.circle.fill" : "globe")
                                    .foregroundStyle(selected ? Brand.success : .secondary)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(n.label).font(.callout.weight(selected ? .semibold : .regular))
                                    Text(URL(string: n.rpc)?.host ?? n.rpc)
                                        .font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .background(selected ? Brand.accent.opacity(0.10) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 220)

            Divider()

            Button { open = false; model.section = .settings } label: {
                Label("Manage networks…", systemImage: "gearshape")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private func Stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.semibold).monospacedDigit())
        }
    }
}
