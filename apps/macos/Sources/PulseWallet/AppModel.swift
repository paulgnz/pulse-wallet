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

@Observable
final class AppModel {
    var section: WalletSection = .wallet
    var accounts: [PulseAccount] = []
    var selectedAccount: PulseAccount?
    var assets: [Asset] = []
    var activity: [ActivityItem] = []
    var isLocked = false

    /// Network this wallet is pointed at (A-Chain testnet by default).
    var endpoint = "https://rpc.a-chain-testnet.protonnz.com"
    var chainName = "A-Chain Testnet"

    init() { loadSampleState() }

    func lock() { isLocked = true }
    func unlock() { isLocked = false }

    func select(_ account: PulseAccount) {
        selectedAccount = account
        // In the real app: refresh balances + activity from RPC/Hyperion.
    }

    /// Placeholder state so the UI is reviewable before RPC wiring lands.
    /// Replaced by live `PulseClient` calls (see Crypto/PulseCore.swift).
    private func loadSampleState() {
        let acct = PulseAccount(
            name: "protonnz",
            permission: "active",
            pubKey: "PUB_R1_562tX4UqQqJqfL3PnKFNYycVMQ1WghKDLzbx9XePwE1zSJj8Zo",
            isHardwareBacked: true)
        accounts = [
            acct,
            PulseAccount(name: "treasury.nz", permission: "active",
                         pubKey: "PUB_R1_7x…ops", isHardwareBacked: false)
        ]
        selectedAccount = acct
        // XPR is the value/transfer token (headline balance); SYS is the system
        // resource token staked for CPU / NET / RAM.
        assets = [
            Asset(symbol: "XPR", amount: 50_000,     precision: 4, contract: "eosio.token", role: .value),
            Asset(symbol: "SYS", amount: 1_284.5012, precision: 4, contract: "pulse.token", role: .resource)
        ]
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        activity = [
            ActivityItem(kind: .received, counterparty: "metallicus", asset: "+250.0000 XPR",
                         memo: "grant", time: now, txid: "a1b2c3"),
            ActivityItem(kind: .sent, counterparty: "treasury.nz", asset: "-12.5000 XPR",
                         memo: "ops", time: now.addingTimeInterval(-3600), txid: "d4e5f6"),
            ActivityItem(kind: .staked, counterparty: "pulse.system", asset: "100.0000 SYS",
                         memo: "CPU/NET", time: now.addingTimeInterval(-86400), txid: "070809")
        ]
    }
}
