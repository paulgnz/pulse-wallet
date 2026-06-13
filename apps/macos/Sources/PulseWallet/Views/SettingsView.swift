import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(ThemeStore.self) private var themeStore
    @State private var requireBiometricsEachTx = true
    @State private var editing: PulseNetwork?
    @State private var addingNew = false
    @State private var importingTheme = false

    var body: some View {
        ScrollView {
            VStack(spacing: Metric.gutter) {
                networks
                branding
                security
                about
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
        .frame(minWidth: 480, minHeight: 520)
        .sheet(item: $editing) { net in NetworkEditSheet(network: net) }
        .sheet(isPresented: $addingNew) { NetworkEditSheet(network: nil) }
        .fileImporter(isPresented: $importingTheme, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                try? themeStore.importTheme(from: url)
            }
        }
    }

    // MARK: Branding / Theme (white-label)
    private var branding: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(title: "Branding", systemImage: "paintpalette")
                    Spacer()
                    Button { importingTheme = true } label: {
                        Label("Import theme…", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.glass).font(.caption)
                    .help("Load a white-label theme (.json)")
                }
                Text("Skin the wallet for your organization. Bundled themes below; drop a custom theme JSON to white-label.")
                    .font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 12)], spacing: 12) {
                    ForEach(themeStore.available) { theme in
                        ThemeSwatch(theme: theme, selected: theme.id == themeStore.current.id) {
                            themeStore.select(theme.name)
                        }
                    }
                }
            }
        }
    }

    // MARK: Networks
    private var networks: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Networks", systemImage: "network")
                Button { addingNew = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.glass)
            }
            ForEach(Array(model.networks.networks.enumerated()), id: \.element.id) { idx, net in
                GlassCard(padding: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: net.id == model.networks.selectedID ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(net.id == model.networks.selectedID ? Brand.success : .secondary)
                            .onTapGesture { model.switchNetwork(net) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(net.label).font(.body.weight(.semibold))
                            Text(net.rpc).font(.caption.monospaced()).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                            if let cid = net.chainId {
                                Text("chain \(cid.prefix(12))…").font(.caption2.monospaced())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        VStack(spacing: 2) {
                            Button { model.networks.move(net, by: -1) } label: { Image(systemName: "chevron.up") }
                                .disabled(idx == 0)
                            Button { model.networks.move(net, by: 1) } label: { Image(systemName: "chevron.down") }
                                .disabled(idx == model.networks.networks.count - 1)
                        }
                        .buttonStyle(.borderless).font(.caption)
                        Menu {
                            Button("Edit…") { editing = net }
                            if net.id != model.networks.selectedID {
                                Button("Set as default") { model.switchNetwork(net) }
                            }
                            Divider()
                            Button("Delete", role: .destructive) { model.networks.delete(net) }
                                .disabled(model.networks.networks.count <= 1)
                        } label: { Image(systemName: "ellipsis.circle") }
                            .menuStyle(.borderlessButton).fixedSize()
                    }
                }
            }
        }
    }

    // MARK: Security
    private var security: some View {
        @Bindable var model = model
        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Security", systemImage: "lock.shield")
                Toggle("Require Touch ID for every transaction", isOn: $requireBiometricsEachTx)
                Divider()
                Toggle("Lock wallet when inactive", isOn: $model.autoLock)
                Divider()
                HStack {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                    Spacer()
                    Picker("", selection: $model.appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }.labelsHidden().pickerStyle(.segmented).fixedSize()
                }
                Divider()
                HStack {
                    Label("Signing key", systemImage: "touchid")
                    Spacer()
                    Text(model.selectedAccount?.isHardwareBacked == true
                         ? "Secure Enclave (hardware)" : "Software / watch-only")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: About
    private var about: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "About", systemImage: "info.circle")
                Text("PulseVM — the native macOS wallet for PulseVM.").font(.callout)
                HStack {
                    Label("Version", systemImage: "number")
                    Spacer()
                    Text(SettingsView.versionString)
                        .font(.callout.monospaced()).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Text("Keys are generated and held in the Secure Enclave; signatures are produced on-device with Touch ID and never leave the chip.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Marketing version + build, with a Debug/Release tag — so it's obvious which
    /// build is running (e.g. the Xcode debug build vs the installed release).
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        #if DEBUG
        let cfg = " · Debug"
        #else
        let cfg = " · Release"
        #endif
        return "\(v) (\(b))\(cfg)"
    }
}

/// A live preview swatch for a theme — a mini wallet card: themed background,
/// a "balance" line, an accent pill (selection/CTA), and the status palette.
private struct ThemeSwatch: View {
    let theme: Theme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(LinearGradient(colors: [Color(hex: theme.navy), Color(hex: theme.ink)],
                                             startPoint: .top, endPoint: .bottom))
                    VStack(alignment: .leading, spacing: 7) {
                        // Faux balance — shows the accent→glow text gradient.
                        Text("1,234").font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(LinearGradient(
                                colors: [Color(hex: theme.accent), Color(hex: theme.glow)],
                                startPoint: .leading, endPoint: .trailing))
                        // Faux selected row — the accent pill (what was system-blue before).
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(hex: theme.accent))
                            .frame(width: 64, height: 12)
                        Spacer(minLength: 0)
                        // Status palette.
                        HStack(spacing: 5) {
                            ForEach([theme.success, theme.warn, theme.danger], id: \.self) { c in
                                Circle().fill(Color(hex: c)).frame(width: 8, height: 8)
                            }
                        }
                    }
                    .padding(10)
                }
                .frame(height: 84)
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.07)))

                HStack(spacing: 5) {
                    Text(theme.name).font(.caption.weight(.semibold))
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(Brand.accent)
                    }
                }
            }
            .padding(7)
            .background(.primary.opacity(selected ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(selected ? Brand.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

/// Add or edit a network; "Test" calls getInfo to fetch chain id + head.
private struct NetworkEditSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let network: PulseNetwork?

    @State private var label = ""
    @State private var rpc = ""
    @State private var hyperion = ""
    @State private var explorer = ""
    @State private var primarySymbol = "XPR"
    @State private var chainId: String?
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(network == nil ? "Add Network" : "Edit Network")
                .font(.title2.weight(.semibold))
            field("Label", "A-Chain Testnet", $label)
            field("RPC endpoint", "https://rpc.…", $rpc, mono: true)
            field("Hyperion endpoint (optional)", "https://hyperion.…", $hyperion, mono: true)
            field("Explorer base (optional)", "https://explorer.…", $explorer, mono: true)
            field("Headline token", "XPR", $primarySymbol)

            HStack {
                Button {
                    Task { await test() }
                } label: {
                    Label(testing ? "Testing…" : "Test connection", systemImage: "antenna.radiowaves.left.and.right")
                }
                .buttonStyle(.glass).disabled(rpc.isEmpty || testing)
                if let r = testResult {
                    Text(r).font(.caption).foregroundStyle(chainId != nil ? Brand.success : Brand.danger)
                        .lineLimit(2)
                }
            }

            Spacer()
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.glass).controlSize(.large)
                Spacer()
                PrimaryButton(title: "Save", systemImage: "checkmark") { save() }
                    .frame(width: 140)
                    .disabled(label.isEmpty || rpc.isEmpty)
            }
        }
        .padding(24).frame(width: 480, height: 440)
        .background(BrandBackground())
        .onAppear {
            if let n = network {
                label = n.label; rpc = n.rpc; hyperion = n.hyperion
                explorer = n.explorer; primarySymbol = n.primarySymbol; chainId = n.chainId
            }
        }
    }

    private func field(_ title: String, _ placeholder: String, _ text: Binding<String>, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            TextField(placeholder, text: text).pulseField(mono: mono)
        }
    }

    private func test() async {
        testing = true; testResult = nil
        defer { testing = false }
        guard let client = PulseRPC(rpc) else { testResult = "Invalid URL"; return }
        do {
            let info = try await client.getInfo()
            chainId = info.chainId
            testResult = "OK · head \(info.headBlockNum) · v\(info.serverVersion)"
        } catch {
            testResult = error.localizedDescription
        }
    }

    private func save() {
        let net = PulseNetwork(
            id: network?.id ?? UUID(),
            label: label, rpc: rpc,
            hyperion: hyperion.isEmpty ? rpc : hyperion,
            explorer: explorer,
            chainId: chainId ?? network?.chainId,
            primarySymbol: primarySymbol.isEmpty ? "XPR" : primarySymbol)
        if network == nil { model.networks.add(net) } else { model.networks.update(net) }
        dismiss()
    }
}
