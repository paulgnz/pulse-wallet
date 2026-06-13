import Foundation
import Observation

enum WalletSection: String, CaseIterable, Identifiable {
    case wallet, send, receive, activity, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .wallet:   return "Wallet"
        case .send:     return "Send"
        case .receive:  return "Receive"
        case .activity: return "Activity"
        case .settings: return "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .wallet:   return "wallet.bifold"
        case .send:     return "arrow.up.right.circle"
        case .receive:  return "arrow.down.left.circle"
        case .activity: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var section: WalletSection = .wallet

    /// Network this wallet is pointed at (A-Chain testnet by default).
    var endpoint = "https://rpc.a-chain-testnet.protonnz.com"
    var hyperionEndpoint = "https://hyperion.a-chain-testnet.protonnz.com"
    var chainName = "A-Chain Testnet"

    /// The token shown as the headline balance (value token; SYS is resource).
    var primarySymbol = "XPR"

    /// Chain logic backed by the Rust core (validated vs pulsevm-js).
    let core: PulseCore = PulseCoreFFI()

    /// Watch account until onboarding (#6) provides a real owned account.
    var accountName = "protonnz"
    var permissionName = "active"

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
