import Foundation
import Observation
import SwiftUI

enum WalletSection: String, CaseIterable, Identifiable {
    case wallet, send, receive, activity, multisig, keys, tools, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .wallet:   return "Wallet"
        case .send:     return "Send"
        case .receive:  return "Receive"
        case .activity: return "Activity"
        case .multisig: return "Multisig"
        case .keys:     return "Keys"
        case .tools:    return "Tools"
        case .settings: return "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .wallet:   return "wallet.bifold"
        case .send:     return "arrow.up.right.circle"
        case .receive:  return "arrow.down.left.circle"
        case .activity: return "clock.arrow.circlepath"
        case .multisig: return "person.2.badge.key"
        case .keys:     return "key.horizontal"
        case .tools:    return "wrench.and.screwdriver"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var section: WalletSection = .wallet

    /// Configured networks (managed in Settings). The active one drives endpoints.
    let networks = NetworkStore()

    var endpoint: String { networks.active.rpc }
    var hyperionEndpoint: String { networks.active.hyperion }
    var chainName: String { networks.active.label }
    /// The token shown as the headline balance (value token; SYS is resource).
    var primarySymbol: String { networks.active.primarySymbol }

    /// Chain logic backed by the Rust core (validated vs pulsevm-js).
    let core: PulseCore = PulseCoreFFI()

    /// Watched accounts (switchable). Real key-owned onboarding lands in #6.
    var accountNames: [String] = ["protonnz"] { didSet { persistAccounts() } }
    var accountName = "protonnz" {
        didSet { UserDefaults.standard.set(accountName, forKey: "wallet.activeAccount") }
    }
    var permissionName = "active"

    /// Set by the account menu's "Import key…" to auto-open the import sheet.
    var requestImportKey = false

    /// An incoming dapp request (pulsevm:// URL scheme) awaiting approval.
    var pendingRequest: DappRequest?

    init() {
        if let data = UserDefaults.standard.data(forKey: "wallet.accounts.v1"),
           let arr = try? JSONDecoder().decode([String].self, from: data), !arr.isEmpty {
            accountNames = arr
        }
        if let a = UserDefaults.standard.string(forKey: "wallet.activeAccount"),
           accountNames.contains(a) {
            accountName = a
        } else {
            accountName = accountNames[0]
        }
        autoLock = UserDefaults.standard.object(forKey: "wallet.autoLock") as? Bool ?? true
        appearance = UserDefaults.standard.string(forKey: "wallet.appearance") ?? "system"
    }

    private func persistAccounts() {
        if let data = try? JSONEncoder().encode(accountNames) {
            UserDefaults.standard.set(data, forKey: "wallet.accounts.v1")
        }
    }

    // Live state, fetched from RPC.
    private(set) var chainInfo: ChainInfo?
    private(set) var account: AccountInfo?
    private(set) var assets: [Asset] = []
    private(set) var activity: [ActivityItem] = []
    private(set) var isLoading = false
    private(set) var loadError: String?

    var isLocked = false
    var autoLock = true { didSet { UserDefaults.standard.set(autoLock, forKey: "wallet.autoLock") } }

    /// "system" | "light" | "dark"
    var appearance = "system" { didSet { UserDefaults.standard.set(appearance, forKey: "wallet.appearance") } }
    var appearanceScheme: ColorScheme? {
        switch appearance { case "light": return .light; case "dark": return .dark; default: return nil }
    }

    private var rpc: PulseRPC? { PulseRPC(endpoint) }
    private var hyperion: Hyperion? { Hyperion(hyperionEndpoint) }

    // MARK: Derived view state

    /// A `PulseAccount` synthesized from live chain data (keeps views simple).
    var selectedAccount: PulseAccount? {
        let activeKey = account?.permissions
            .first { $0.permName == permissionName }?
            .requiredAuth.keys.first?.key
        return PulseAccount(
            name: account?.accountName ?? accountName,
            permission: permissionName,
            pubKey: activeKey ?? "",
            isHardwareBacked: activeKey?.hasPrefix("PUB_R1_") ?? false)
    }
    var accounts: [PulseAccount] { selectedAccount.map { [$0] } ?? [] }

    var coreSymbol: String? { account?.coreSymbol }

    /// Permissions on the loaded account that `pub` is a key of (e.g. ["owner","active"]).
    func permissions(forKey pub: String?) -> [String] {
        guard let pub, !pub.isEmpty, let perms = account?.permissions else { return [] }
        return perms.filter { p in p.requiredAuth.keys.contains { $0.key == pub } }.map(\.permName)
    }

    /// Default `permissionName` to a permission the active key actually controls.
    func selectBestPermission(forKey pub: String?) {
        let authorized = permissions(forKey: pub)
        if !authorized.contains(permissionName) {
            permissionName = authorized.first ?? "active"
        }
    }

    func explorerAccountURL(_ name: String) -> URL? { networks.active.accountURL(name) }
    func explorerTxURL(_ txid: String) -> URL? { networks.active.txURL(txid) }

    /// Headline asset: the primary value token if held, else first value, else first.
    var primaryAsset: Asset? {
        assets.first { $0.symbol == primarySymbol }
            ?? assets.first { $0.role == .value }
            ?? assets.first
    }

    /// The network is paused if the head block hasn't advanced recently.
    var networkPaused: Bool {
        guard let t = chainInfo?.headBlockTime, let d = Self.parseChainTime(t) else { return false }
        return Date().timeIntervalSince(d) > 120
    }

    // MARK: Actions

    func lock() { isLocked = true }
    func unlock() { isLocked = false }

    func select(_ account: PulseAccount) {
        accountName = account.name
        Task { await refresh() }
    }

    func switchAccount(_ name: String) {
        guard name != accountName else { return }
        accountName = name
        Task { await refresh() }
    }

    /// Add a watch account by name (lowercased). Refresh validates it exists.
    func addAccount(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !n.isEmpty, !accountNames.contains(n) else { return }
        accountNames.append(n)
        accountName = n
        Task { await refresh() }
    }

    func switchNetwork(_ network: PulseNetwork) {
        networks.select(network)
        Task { await refresh() }
    }

    /// Handle an incoming pulsevm:// deep link from a dapp (login or sign).
    func handleURL(_ url: URL) {
        guard url.scheme == "pulsevm" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ name: String) -> String? { items.first { $0.name == name }?.value }
        let callback = q("callback").flatMap(URL.init(string:))
        switch url.host {
        case "login":
            pendingRequest = .login(callback: callback)
        case "sign":
            guard let packed = q("packed_trx") else { return }
            let cid = q("chain_id") ?? networks.active.chainId ?? chainInfo?.chainId ?? ""
            // Query values use form-encoding where '+' means space.
            let summary = (q("summary") ?? "External transaction").replacingOccurrences(of: "+", with: " ")
            pendingRequest = .sign(chainId: cid, packedTrx: packed, summary: summary, callback: callback)
        default:
            break
        }
    }

    /// Accounts a public key can sign for (reverse lookup via Hyperion).
    func keyAccounts(_ publicKey: String) async -> [String] {
        (try? await hyperion?.getKeyAccounts(publicKey)) ?? []
    }

    /// The pulse.msig contract account on the active network.
    var msigContract: String { "pulse.msig" }

    struct ProposalRow: Decodable, Sendable { let proposalName: String }

    /// Proposal names created by `proposer`.
    func proposals(by proposer: String) async -> [String] {
        guard let rpc else { return [] }
        let rows = (try? await rpc.getTableRows(
            code: msigContract, scope: proposer, table: "proposal", as: ProposalRow.self)) ?? []
        return rows.map(\.proposalName)
    }

    // Approvals inbox — who has approved / is still requested on each proposal.
    private struct ApprovalLevel: Decodable, Sendable {
        struct Level: Decodable, Sendable { let actor: String; let permission: String }
        let level: Level
    }
    private struct Approvals2Row: Decodable, Sendable {
        let proposalName: String
        let requestedApprovals: [ApprovalLevel]
        let providedApprovals: [ApprovalLevel]
    }
    struct ProposalStatus: Identifiable, Sendable {
        let name: String
        let provided: [String]
        let requested: [String]
        var id: String { name }
    }

    /// Per-proposal approval status (provided vs still-requested approvers).
    func proposalStatuses(by proposer: String) async -> [ProposalStatus] {
        guard let rpc else { return [] }
        let rows = (try? await rpc.getTableRows(
            code: msigContract, scope: proposer, table: "approvals2", as: Approvals2Row.self)) ?? []
        return rows.map { r in
            ProposalStatus(name: r.proposalName,
                           provided: r.providedApprovals.map(\.level.actor),
                           requested: r.requestedApprovals.map(\.level.actor))
        }
    }

    /// Build the TAPOS triple from current chain head (nil if not connected).
    func taposContext() -> (chainId: String, refBlockNum: UInt16, refBlockPrefix: UInt32, expiration: UInt32)? {
        guard let info = chainInfo, let prefix = Self.refBlockPrefix(blockIdHex: info.headBlockId)
        else { return nil }
        let chainId = networks.active.chainId ?? info.chainId
        return (chainId, UInt16(truncatingIfNeeded: info.headBlockNum), prefix,
                UInt32(Date().timeIntervalSince1970) + 3600)  // proposals: longer expiry
    }

    /// Broadcast a signed transaction; returns the tx id.
    func broadcast(signatures: [String], packedTrx: String) async throws -> String {
        guard let rpc else { throw PulseRPC.Failure(message: "Invalid endpoint") }
        return try await rpc.issueTx(signatures: signatures, packedTrx: packedTrx)
    }

    /// Pull chain info + the watched account's real balances/resources.
    func refresh() async {
        guard let rpc else { loadError = "Invalid endpoint"; return }
        isLoading = true
        loadError = nil
        do {
            async let info = rpc.getInfo()
            async let acct = rpc.getAccount(accountName)
            let (i, a) = try await (info, acct)
            chainInfo = i
            account = a

            // Prefer Hyperion for full multi-token discovery; fall back to the
            // system core balance if the indexer is unavailable.
            if let tokens = try? await hyperion?.getTokens(accountName), !tokens.isEmpty {
                assets = sorted(tokens.map(Asset.init(token:)))
            } else {
                assets = sorted(Self.coreAssets(from: a))
            }

            // Recent history (best-effort; empty if indexer unavailable).
            if let actions = try? await hyperion?.getActions(accountName) {
                let me = accountName
                activity = actions.compactMap { Self.activityItem(from: $0, account: me) }
            }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    /// Value tokens first (primary token leading), resource tokens last.
    private func sorted(_ assets: [Asset]) -> [Asset] {
        let primary = primarySymbol
        func rank(_ a: Asset) -> Int {
            if a.symbol == primary { return 0 }
            return a.role == .value ? 1 : 2
        }
        return assets.sorted { lhs, rhs in
            let (l, r) = (rank(lhs), rank(rhs))
            return l != r ? l < r : lhs.symbol < rhs.symbol
        }
    }

    /// Map a Hyperion action to a display row (transfers get direction/amount).
    private static func activityItem(from action: Hyperion.ActionItem, account: String) -> ActivityItem? {
        let d = action.act.data
        let time = parseChainTime(action.timestamp) ?? Date(timeIntervalSince1970: 0)
        if action.act.name == "transfer", let qty = d.quantity {
            let outgoing = d.from == account
            return ActivityItem(
                kind: outgoing ? .sent : .received,
                counterparty: outgoing ? (d.to ?? "—") : (d.from ?? "—"),
                asset: (outgoing ? "-" : "+") + qty,
                memo: d.memo ?? "",
                time: time,
                txid: action.trxId)
        }
        // Non-transfer action → generic contract row.
        return ActivityItem(
            kind: .contract,
            counterparty: action.act.account,
            asset: action.act.name,
            memo: d.memo ?? "",
            time: time,
            txid: String(action.trxId.prefix(8)))
    }

    private static func coreAssets(from account: AccountInfo) -> [Asset] {
        guard let bal = account.coreLiquidBalance,
              let asset = Asset(balanceString: bal, contract: "pulse.token",
                                role: account.coreSymbol == "SYS" ? .resource : .value)
        else { return [] }
        return [asset]
    }

    /// Everything the core needs to build + sign a transfer.
    struct TransferDraft: Sendable {
        let from, to, quantity, memo, contract, actor, permission, chainId: String
        let refBlockNum: UInt16
        let refBlockPrefix: UInt32
        let expiration: UInt32
    }

    /// Assemble a transfer draft from live chain state. nil if data is missing
    /// (not connected, unknown token, etc.).
    func makeTransferDraft(to: String, amount: String, symbol: String, memo: String) -> TransferDraft? {
        guard let info = chainInfo,
              let asset = assets.first(where: { $0.symbol == symbol }),
              let qty = Self.formatQuantity(amount, precision: asset.precision, symbol: symbol),
              let prefix = Self.refBlockPrefix(blockIdHex: info.headBlockId)
        else { return nil }
        let chainId = networks.active.chainId ?? info.chainId
        return TransferDraft(
            from: accountName, to: to.trimmingCharacters(in: .whitespaces),
            quantity: qty, memo: memo, contract: asset.contract,
            actor: accountName, permission: permissionName, chainId: chainId,
            refBlockNum: UInt16(truncatingIfNeeded: info.headBlockNum),
            refBlockPrefix: prefix,
            expiration: UInt32(Date().timeIntervalSince1970) + 120)
    }

    static func formatQuantity(_ amount: String, precision: Int, symbol: String) -> String? {
        guard let d = Decimal(string: amount.trimmingCharacters(in: .whitespaces)) else { return nil }
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.minimumIntegerDigits = 1
        f.minimumFractionDigits = precision
        f.maximumFractionDigits = precision
        guard let s = f.string(from: NSDecimalNumber(decimal: d)) else { return nil }
        return "\(s) \(symbol)"
    }

    /// ref_block_prefix = uint32 LE at bytes [8..12] of the block id.
    static func refBlockPrefix(blockIdHex: String) -> UInt32? {
        guard let d = Data(hexString: blockIdHex), d.count >= 12 else { return nil }
        return UInt32(d[8]) | (UInt32(d[9]) << 8) | (UInt32(d[10]) << 16) | (UInt32(d[11]) << 24)
    }

    /// Parse chain timestamps like "2026-06-11T22:18:20.000" (UTC, no zone).
    static func parseChainTime(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        return f.date(from: s)
    }
}
