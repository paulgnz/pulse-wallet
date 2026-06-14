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

/// Live network indicator in the toolbar — glass capsule, current macOS styling.
struct NetworkPill: View {
    @Environment(AppModel.self) private var model

    private var paused: Bool { model.networkPaused }
    private var dot: Color { model.chainInfo == nil ? Brand.warn : (paused ? Brand.warn : Brand.success) }

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(dot).frame(width: 6, height: 6)
                .overlay(Circle().fill(dot).blur(radius: 2.5).opacity(0.7))
            Text(model.chainName).font(.callout.weight(.semibold))
            if paused, let n = model.chainInfo?.headBlockNum {
                Text("paused").font(.caption.weight(.medium)).foregroundStyle(Brand.warn)
                Text(n.formatted()).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2).padding(.horizontal, 4)
        .fixedSize()
        // The .principal toolbar item already provides a glass capsule on Tahoe —
        // don't add a second one here, or it renders as a pill-inside-a-pill.
        .help(model.chainInfo.map { "Head \($0.headBlockNum) · v\($0.serverVersion)" } ?? "Connecting…")
    }
}
