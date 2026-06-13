import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        @Bindable var model = model

        NavigationSplitView(columnVisibility: $columnVisibility) {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            detail
                .navigationTitle(model.section.title)
                .toolbar { ToolbarItem(placement: .principal) { NetworkPill() } }
        }
        .background(Brand.navy.gradient.opacity(0.35))
        .overlay { if model.isLocked { LockScreen() } }
        .animation(.smooth, value: model.isLocked)
    }

    @ViewBuilder private var detail: some View {
        switch model.section {
        case .wallet:   DashboardView()
        case .send:     SendView()
        case .receive:  ReceiveView()
        case .activity: ActivityView()
        case .settings: SettingsView()
        }
    }
}

/// Live network indicator in the toolbar — glass capsule, current macOS styling.
struct NetworkPill: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Brand.success).frame(width: 7, height: 7)
                .shadow(color: Brand.success.opacity(0.8), radius: 4)
            Text(model.chainName).font(.callout.weight(.medium))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
    }
}
