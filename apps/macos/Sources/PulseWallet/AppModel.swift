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
    var chainName = "A-Chain Testnet"

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
            assets = Self.assets(from: a)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private static func assets(from account: AccountInfo) -> [Asset] {
        var out: [Asset] = []
        // The core liquid (spendable) token — SYS on A-Chain, XPR on mainnet.
        if let bal = account.coreLiquidBalance,
           let asset = Asset(balanceString: bal,
                             contract: account.coreSymbol == "SYS" ? "pulse.token" : "eosio.token",
                             role: .value) {
            out.append(asset)
        }
        return out
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
