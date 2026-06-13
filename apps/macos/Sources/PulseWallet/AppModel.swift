import Foundation
import Observation

enum WalletSection: String, CaseIterable, Identifiable {
    case wallet, send, receive, activity, keys, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .wallet:   return "Wallet"
        case .send:     return "Send"
        case .receive:  return "Receive"
        case .activity: return "Activity"
        case .keys:     return "Keys"
        case .settings: return "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .wallet:   return "wallet.bifold"
        case .send:     return "arrow.up.right.circle"
        case .receive:  return "arrow.down.left.circle"
        case .activity: return "clock.arrow.circlepath"
        case .keys:     return "key.horizontal"
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

    /// Parse chain timestamps like "2026-06-11T22:18:20.000" (UTC, no zone).
    static func parseChainTime(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        return f.date(from: s)
    }
}
