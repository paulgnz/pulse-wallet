import SwiftUI

/// Full account-permission management, mirroring a block explorer's auth tools:
///  • Simple   — set one permission to a threshold of keys (the common case).
///  • Advanced — full editor: per-permission keys + account auths + waits, add/delete permission.
///  • Link Auth — bind a permission to a specific contract::action (linkauth / unlinkauth).
struct PermissionsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(KeyStore.self) private var keyStore
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable, Identifiable { case simple = "Simple", advanced = "Advanced", link = "Link Auth"; var id: String { rawValue } }
    @State private var tab: Tab = .simple
    @State private var status: String?
    @State private var working = false
    @State private var loaded = false

    // Simple
    @State private var sPermission = "active"
    @State private var sParent = "owner"
    @State private var sThreshold = "1"
    @State private var sKeys = ""

    // Advanced
    @State private var perms: [EditablePermission] = []
    @State private var expanded: Set<String> = []

    // Link Auth
    @State private var lPermission = ""
    @State private var lContract = ""
    @State private var lAction = ""

    private let systemContract = "pulse"
    private typealias Tapos = (chainId: String, refBlockNum: UInt16, refBlockPrefix: UInt32, expiration: UInt32)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Permissions").font(.title2.weight(.semibold))
                InfoHint(text: Explain.ownerVsActive, title: "How permissions work")
                Spacer()
                Text(model.accountName).font(.callout).foregroundStyle(.secondary)
            }
            Picker("", selection: $tab) { ForEach(Tab.allCases) { Text($0.rawValue).tag($0) } }
                .labelsHidden().pickerStyle(.segmented)

            if !model.keyControlsAccount(keyStore.activeKey?.pubKey) {
                Label("Your active signing key doesn't control \(model.accountName) — changes can't be signed. Set a controlling key active in Keys.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(Brand.warn)
            }

            ScrollView {
                switch tab {
                case .simple:   simpleTab
                case .advanced: advancedTab
                case .link:     linkTab
                }
            }

            if let status {
                Text(status).font(.caption)
                    .foregroundStyle(status.hasPrefix("Submitted") ? Brand.success : Brand.danger)
                    .textSelection(.enabled)
            }
            HStack {
                Button("Close") { dismiss() }.buttonStyle(.glass).controlSize(.large)
                Spacer()
                if working { ProgressView().controlSize(.small) }
            }
        }
        .padding(24).frame(width: 580, height: 660)
        .background(BrandBackground())
        .onAppear { if !loaded { load(); loaded = true } }
    }

    // MARK: Simple
    private var simpleTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set \(model.accountName)’s permission to a threshold of weighted keys. The simplest, safest change.")
                .font(.caption).foregroundStyle(.secondary)
            labeled("Permission") { TextField("active", text: $sPermission).pulseField(mono: true) }
            HStack {
                labeled("Parent") { TextField("owner", text: $sParent).pulseField(mono: true) }
                labeled("Threshold") { TextField("1", text: $sThreshold).pulseField(mono: true) }.frame(width: 120)
            }
            labeled("Keys (PUB_…@weight; one per line)") {
                TextEditor(text: $sKeys).font(.caption.monospaced()).frame(height: 90)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            }
            HStack {
                Button("Load current") { loadSimple() }.buttonStyle(.link).font(.caption)
                Button("Use my held keys") { sKeys = keyStore.keys.map { "\($0.pubKey)@1" }.joined(separator: ";\n") }
                    .buttonStyle(.link).font(.caption)
            }
            PrimaryButton(title: "Update authority", systemImage: "checkmark.shield") { submitSimple() }
                .disabled(working || sKeys.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: Advanced
    private var advancedTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit each permission's keys, account authorities, and waits. Add or delete permissions. Each card saves independently.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach($perms) { $p in
                permCard($p)
            }
            Button { perms.append(.blank()) } label: {
                Label("Add new permission", systemImage: "plus")
            }.buttonStyle(.glass).controlSize(.large)
        }
    }

    @ViewBuilder private func permCard(_ p: Binding<EditablePermission>) -> some View {
        let isOpen = expanded.contains(p.wrappedValue.id)
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(p.wrappedValue.name.isEmpty ? "New permission" : "@\(p.wrappedValue.name)")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if isOpen {
                        if !p.wrappedValue.isNew {
                            Button(role: .destructive) { submitDelete(p.wrappedValue) } label: {
                                Label("Delete", systemImage: "xmark").font(.caption)
                            }.buttonStyle(.glass).tint(Brand.danger).controlSize(.small)
                        }
                        Button { submitAdvanced(p.wrappedValue) } label: {
                            Label("Save", systemImage: "checkmark").font(.caption)
                        }.buttonStyle(.glassProminent).tint(Brand.success).controlSize(.small)
                    }
                    Button { toggle(p.wrappedValue.id) } label: {
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    }.buttonStyle(.plain)
                }
                if isOpen {
                    HStack {
                        labeled("Name") { TextField("e.g. bprewards", text: p.name).pulseField(mono: true) }
                        labeled("Parent") { TextField("owner", text: p.parent).pulseField(mono: true) }.frame(width: 130)
                        labeled("Threshold") { TextField("1", text: p.threshold).pulseField(mono: true) }.frame(width: 90)
                    }
                    editList("KEYS", add: { p.wrappedValue.keys.append(.init(a: "", b: "1")) }, addIcon: "key") {
                        ForEach(p.keys) { $k in
                            twoField($k.a, "PUB_K1_… / PUB_R1_…", $k.b) { remove(p.keys, $k.wrappedValue.id) }
                        }
                    }
                    editList("ACCOUNTS", add: { p.wrappedValue.accounts.append(.init(a: "", b: "active", c: "1")) }, addIcon: "person") {
                        ForEach(p.accounts) { $a in
                            threeField($a.a, "actor", $a.b, "perm", $a.c) { remove(p.accounts, $a.wrappedValue.id) }
                        }
                    }
                    editList("WAITS (seconds)", add: { p.wrappedValue.waits.append(.init(a: "", b: "1")) }, addIcon: "clock") {
                        ForEach(p.waits) { $w in
                            twoField($w.a, "seconds", $w.b) { remove(p.waits, $w.wrappedValue.id) }
                        }
                    }
                }
            }
        }
    }

    // MARK: Link Auth
    private var linkTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Link a permission so it can authorize a specific contract action — e.g. let a `bprewards` permission call `eosio::voteproducer`. Leave Action blank to link every action of the contract.")
                .font(.caption).foregroundStyle(.secondary)
            labeled("Permission (the requirement that may sign)") {
                TextField("e.g. bprewards", text: $lPermission).pulseField(mono: true)
            }
            labeled("Contract (code)") { TextField("e.g. pulse / eosio", text: $lContract).pulseField(mono: true) }
            labeled("Action (type) — optional") { TextField("e.g. voteproducer", text: $lAction).pulseField(mono: true) }
            HStack {
                PrimaryButton(title: "Link Auth", systemImage: "link") { submitLink(link: true) }
                    .disabled(working || lPermission.isEmpty || lContract.isEmpty)
                Button { submitLink(link: false) } label: {
                    Label("Unlink Auth", systemImage: "link.badge.minus").frame(maxWidth: .infinity).padding(.vertical, 4)
                }.buttonStyle(.glass).controlSize(.large).disabled(working || lContract.isEmpty)
            }
        }
    }

    // MARK: Submit helpers
    private func submit(_ reason: String, _ build: @escaping (Tapos) throws -> BuiltTx) {
        guard model.keyControlsAccount(keyStore.activeKey?.pubKey) else {
            status = "Your active key doesn't control \(model.accountName)."; return
        }
        guard let ctx = model.taposContext() else { status = "Not connected."; return }
        working = true; status = nil
        Task {
            do {
                let tx = try build(ctx)
                guard let pre = Data(hexString: tx.preimage) else { status = "bad preimage"; working = false; return }
                let sig = try await keyStore.sign(preImage: pre, reason: reason)
                let txid = try await model.broadcast(signatures: [sig], packedTrx: tx.packed)
                status = model.networkPaused
                    ? "Submitted ✓ — queued. Applies once validators resume."
                    : "Submitted ✓ — \(txid)"
                await model.refresh()
                load()
                working = false
            } catch { status = error.localizedDescription; working = false }
        }
    }

    private func submitSimple() {
        guard let th = UInt32(sThreshold.trimmingCharacters(in: .whitespaces)) else { status = "Bad threshold."; return }
        let keyStr = sKeys.replacingOccurrences(of: "\n", with: "")
        submit("Update \(model.accountName)@\(sPermission)") { ctx in
            try model.core.buildUpdateAuth(systemContract: systemContract, account: model.accountName,
                permission: sPermission, parent: sParent, threshold: th, keys: keyStr,
                authActor: model.accountName, authPerm: model.permissionName, chainId: ctx.chainId,
                refBlockNum: ctx.refBlockNum, refBlockPrefix: ctx.refBlockPrefix, expiration: ctx.expiration)
        }
    }

    private func submitAdvanced(_ p: EditablePermission) {
        guard let th = UInt32(p.threshold.trimmingCharacters(in: .whitespaces)) else { status = "Bad threshold."; return }
        guard !p.name.isEmpty else { status = "Permission needs a name."; return }
        let keyStr = p.keys.filter { !$0.a.isEmpty }.map { "\($0.a)@\($0.b.isEmpty ? "1" : $0.b)" }.joined(separator: ";")
        let accStr = p.accounts.filter { !$0.a.isEmpty }.map { "\($0.a)@\($0.b.isEmpty ? "active" : $0.b)@\($0.c.isEmpty ? "1" : $0.c)" }.joined(separator: ";")
        let waitStr = p.waits.filter { !$0.a.isEmpty }.map { "\($0.a)@\($0.b.isEmpty ? "1" : $0.b)" }.joined(separator: ";")
        submit("Update \(model.accountName)@\(p.name)") { ctx in
            try model.core.buildUpdateAuthFull(systemContract: systemContract, account: model.accountName,
                permission: p.name, parent: p.parent.isEmpty ? "owner" : p.parent, threshold: th,
                keys: keyStr, accounts: accStr, waits: waitStr,
                authActor: model.accountName, authPerm: model.permissionName, chainId: ctx.chainId,
                refBlockNum: ctx.refBlockNum, refBlockPrefix: ctx.refBlockPrefix, expiration: ctx.expiration)
        }
    }

    private func submitDelete(_ p: EditablePermission) {
        submit("Delete \(model.accountName)@\(p.name)") { ctx in
            try model.core.buildDeleteAuth(systemContract: systemContract, account: model.accountName,
                permission: p.originalName.isEmpty ? p.name : p.originalName,
                authActor: model.accountName, authPerm: model.permissionName, chainId: ctx.chainId,
                refBlockNum: ctx.refBlockNum, refBlockPrefix: ctx.refBlockPrefix, expiration: ctx.expiration)
        }
    }

    private func submitLink(link: Bool) {
        let reason = "\(link ? "Link" : "Unlink") \(lContract)::\(lAction.isEmpty ? "*" : lAction)"
        submit(reason) { ctx in
            if link {
                try model.core.buildLinkAuth(systemContract: systemContract, account: model.accountName,
                    code: lContract, type: lAction, requirement: lPermission,
                    authActor: model.accountName, authPerm: model.permissionName, chainId: ctx.chainId,
                    refBlockNum: ctx.refBlockNum, refBlockPrefix: ctx.refBlockPrefix, expiration: ctx.expiration)
            } else {
                try model.core.buildUnlinkAuth(systemContract: systemContract, account: model.accountName,
                    code: lContract, type: lAction,
                    authActor: model.accountName, authPerm: model.permissionName, chainId: ctx.chainId,
                    refBlockNum: ctx.refBlockNum, refBlockPrefix: ctx.refBlockPrefix, expiration: ctx.expiration)
            }
        }
    }

    // MARK: Load / state
    private func load() {
        guard let account = model.account else { return }
        perms = account.permissions.map { EditablePermission(from: $0) }
        if sKeys.isEmpty { loadSimple() }
        if expanded.isEmpty, let first = perms.first(where: { $0.name == "active" }) { expanded.insert(first.id) }
    }
    private func loadSimple() {
        guard let perm = model.account?.permissions.first(where: { $0.permName == sPermission }) else { return }
        sThreshold = String(perm.requiredAuth.threshold)
        sParent = perm.parent
        sKeys = perm.requiredAuth.keys.map { "\($0.key)@\($0.weight)" }.joined(separator: ";\n")
    }
    private func toggle(_ id: String) { if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) } }
    private func remove<T: Identifiable>(_ arr: Binding<[T]>, _ id: T.ID) { arr.wrappedValue.removeAll { $0.id == id } }

    // MARK: Small builders
    private func labeled(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            content()
        }
    }
    private func editList(_ title: String, add: @escaping () -> Void, addIcon: String,
                          @ViewBuilder _ rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            rows()
            Button { add() } label: { Label("Add", systemImage: addIcon).font(.caption) }
                .buttonStyle(.glass).controlSize(.small)
        }
        .padding(.vertical, 4)
    }
    private func twoField(_ a: Binding<String>, _ ap: String, _ b: Binding<String>, _ del: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            TextField(ap, text: a).pulseField(mono: true)
            TextField("w", text: b).pulseField(mono: true).frame(width: 50)
            Button { del() } label: { Image(systemName: "minus.circle").foregroundStyle(Brand.danger) }.buttonStyle(.plain)
        }
    }
    private func threeField(_ a: Binding<String>, _ ap: String, _ b: Binding<String>, _ bp: String, _ c: Binding<String>, _ del: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            TextField(ap, text: a).pulseField(mono: true)
            TextField(bp, text: b).pulseField(mono: true).frame(width: 90)
            TextField("w", text: c).pulseField(mono: true).frame(width: 50)
            Button { del() } label: { Image(systemName: "minus.circle").foregroundStyle(Brand.danger) }.buttonStyle(.plain)
        }
    }
}

// MARK: - Editable model

/// A permission being edited in the Advanced tab. Strings throughout so the
/// fields bind directly to TextFields; parsed/validated on save.
struct EditablePermission: Identifiable {
    let id: String
    var name: String
    var parent: String
    var threshold: String
    var keys: [Pair]
    var accounts: [Triple]
    var waits: [Pair]
    var isNew: Bool
    var originalName: String

    struct Pair: Identifiable { let id = UUID().uuidString; var a: String; var b: String }
    struct Triple: Identifiable { let id = UUID().uuidString; var a: String; var b: String; var c: String }

    init(from p: Permission) {
        id = p.permName
        name = p.permName
        parent = p.parent
        threshold = String(p.requiredAuth.threshold)
        keys = p.requiredAuth.keys.map { Pair(a: $0.key, b: String($0.weight)) }
        accounts = []
        waits = []
        isNew = false
        originalName = p.permName
    }
    private init() {
        id = UUID().uuidString; name = ""; parent = "active"; threshold = "1"
        keys = []; accounts = []; waits = []; isNew = true; originalName = ""
    }
    static func blank() -> EditablePermission { .init() }
}
