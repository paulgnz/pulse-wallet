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
            detail
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
        .background(Brand.navy.gradient.opacity(0.35))
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
        case .activity: ActivityView()
        case .multisig: MultisigView()
        case .keys:     KeysView()
        case .settings: SettingsView()
        }
    }
}

/// Live network indicator in the toolbar — glass capsule, current macOS styling.
struct NetworkPill: View {
    @Environment(AppModel.self) private var model

    private var paused: Bool { model.networkPaused }
    private var dot: Color { model.chainInfo == nil ? Brand.warn : (paused ? Brand.warn : Brand.success) }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 7, height: 7)
                .shadow(color: dot.opacity(0.8), radius: 4)
            Text(model.chainName).font(.callout.weight(.medium))
            if paused, let n = model.chainInfo?.headBlockNum {
                Text("· paused @ \(n)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
        .help(model.chainInfo.map { "Head \($0.headBlockNum) · v\($0.serverVersion)" } ?? "Connecting…")
    }
}
