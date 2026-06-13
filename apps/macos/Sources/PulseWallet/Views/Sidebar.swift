import SwiftUI

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        // Custom selection (not List's binding) so the highlight follows the
        // active theme accent on every palette — macOS's native sidebar
        // selection ignores SwiftUI .tint() and forces the system accent.
        List {
            Section {
                ForEach(WalletSection.allCases) { item in
                    SidebarRow(item: item, selected: model.section == item) { model.section = item }
                        .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) { BrandHeader() }
        .safeAreaInset(edge: .bottom) { AccountSwitcher() }
    }
}

/// A sidebar item with theme-controlled selection (solid accent fill +
/// contrast-aware text), replacing the system blue highlight.
private struct SidebarRow: View {
    let item: WalletSection
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(item.title, systemImage: item.symbol)
                .font(.body.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Brand.onAccent : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selected ? AnyShapeStyle(Brand.accent)
                                       : AnyShapeStyle(hovering ? Color.primary.opacity(0.07) : Color.clear))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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

/// Bottom-pinned account chooser: switch accounts, import a key, or (soon)
/// create an account.
private struct AccountSwitcher: View {
    @Environment(AppModel.self) private var model
    @Environment(KeyStore.self) private var keyStore
    @State private var showAddAccount = false

    /// Permissions the active key can sign for on the current account.
    private var authorizedPermissions: [String] { model.permissions(forKey: keyStore.activeKey?.pubKey) }

    var body: some View {
        Menu {
            Section("Accounts") {
                ForEach(model.accountNames, id: \.self) { name in
                    Button { model.switchAccount(name) } label: {
                        Label(name, systemImage: name == model.accountName ? "checkmark" : "person.crop.circle")
                    }
                }
            }
            if !authorizedPermissions.isEmpty {
                Section("Sign with permission") {
                    ForEach(authorizedPermissions, id: \.self) { perm in
                        Button { model.permissionName = perm } label: {
                            Label(perm == "owner" ? "@owner — elevated" : "@\(perm)",
                                  systemImage: perm == model.permissionName ? "checkmark"
                                             : (perm == "owner" ? "exclamationmark.shield" : "key"))
                        }
                    }
                }
            }
            Divider()
            Button { showAddAccount = true } label: {
                Label("Add account…", systemImage: "plus")
            }
            Button {
                model.section = .keys
                model.requestImportKey = true
            } label: {
                Label("Import key…", systemImage: "square.and.arrow.down")
            }
            Button { } label: { Label("Create account (coming soon)", systemImage: "sparkles") }
                .disabled(true)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: (model.selectedAccount?.isHardwareBacked ?? false) ? "touchid" : "person.crop.circle")
                    .font(.title3)
                    .foregroundStyle(Brand.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.accountName)
                        .font(.callout.weight(.semibold))
                    HStack(spacing: 4) {
                        if model.signingWithOwner {
                            Image(systemName: "exclamationmark.shield.fill").font(.caption2)
                        }
                        Text("@\(model.permissionName)")
                            .font(.caption)
                    }
                    .foregroundStyle(model.signingWithOwner ? Brand.danger : .secondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))   // whole capsule is clickable, not just the text
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .padding(12)
        .sheet(isPresented: $showAddAccount) { AddAccountSheet() }
        .task(id: "\(model.accountName)\(model.account?.accountName ?? "")\(keyStore.activeKeyID ?? "")") {
            model.selectBestPermission(forKey: keyStore.activeKey?.pubKey)
        }
    }
}

/// Add a watch account by name (validated on refresh).
private struct AddAccountSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 36)).foregroundStyle(Brand.brandGradient)
                Text("Add account").font(.title2.weight(.semibold))
                Text("Enter a PulseVM account name to watch. Signing requires a key you control (Keys).")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            TextField("e.g. treasury.nz", text: $name)
                .pulseField(mono: true)
            Spacer()
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.glass).controlSize(.large)
                PrimaryButton(title: "Add", systemImage: "plus") {
                    model.addAccount(name); dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24).frame(width: 420, height: 300)
        .background(BrandBackground())
    }
}
