import Foundation

/// A PulseVM account (named, human-readable — the institutional primitive).
struct PulseAccount: Identifiable, Hashable {
    var id: String { name }
    let name: String                 // e.g. "protonnz"
    let permission: String           // e.g. "active"
    let pubKey: String               // PUB_R1_...
    var isHardwareBacked: Bool       // Secure Enclave key?
}

/// Whether a token is the spendable value token or a staked system resource.
enum AssetRole { case value, resource }

/// A token balance held by an account.
struct Asset: Identifiable, Hashable {
    var id: String { symbol }
    let symbol: String               // "XPR" (value), "SYS" (resource)
    let amount: Decimal
    let precision: Int
    let contract: String             // "eosio.token", "pulse.token"
    var role: AssetRole = .value

    var formatted: String {
        let f = NSDecimalNumber(decimal: amount)
        return "\(f.stringValue) \(symbol)"
    }
}

enum ActivityKind: String {
    case sent, received, staked, contract
    var symbol: String {
        switch self {
        case .sent:      return "arrow.up.right"
        case .received:  return "arrow.down.left"
        case .staked:    return "lock.shield"
        case .contract:  return "gearshape.2"
        }
    }
}

struct ActivityItem: Identifiable, Hashable {
    let id = UUID()
    let kind: ActivityKind
    let counterparty: String
    let asset: String
    let memo: String
    let time: Date
    let txid: String
}
