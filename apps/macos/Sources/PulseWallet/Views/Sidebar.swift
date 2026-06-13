import SwiftUI

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        List(selection: $model.section) {
            Section {
                ForEach(WalletSection.allCases) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) { BrandHeader() }
        .safeAreaInset(edge: .bottom) { AccountSwitcher() }
    }
}

private struct BrandHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Brand.brandGradient).frame(width: 30, height: 30)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("PulseVM").font(.headline)
                Text("Wallet").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)
    }
}

/// Bottom-pinned account chooser with a hardware-key badge.
private struct AccountSwitcher: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            ForEach(model.accounts) { acct in
                Button {
                    model.select(acct)
                } label: {
                    Label(acct.name, systemImage: acct.isHardwareBacked ? "touchid" : "key")
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: (model.selectedAccount?.isHardwareBacked ?? false) ? "touchid" : "person.crop.circle")
                    .font(.title3)
                    .foregroundStyle(Brand.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.selectedAccount?.name ?? "—")
                        .font(.callout.weight(.semibold))
                    Text("@\(model.selectedAccount?.permission ?? "active")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .padding(12)
    }
}
