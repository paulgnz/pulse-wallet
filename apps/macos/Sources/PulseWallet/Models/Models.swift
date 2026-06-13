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
        return "\(Asset.grouped(amount, precision: precision)) \(symbol)"
    }

    /// Thousands-separated, fixed-precision amount (e.g. 99,973.4854). Locale-fixed
    /// to comma-grouping + period-decimal so crypto amounts read consistently.
    static func grouped(_ amount: Decimal, precision: Int) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.usesGroupingSeparator = true
        nf.locale = Locale(identifier: "en_US")
        nf.minimumFractionDigits = precision
        nf.maximumFractionDigits = precision
        return nf.string(from: NSDecimalNumber(decimal: amount)) ?? NSDecimalNumber(decimal: amount).stringValue
    }
}

extension Asset {
    /// Parse an Antelope balance like "1000.0000 SYS". (In an extension so the
    /// memberwise initializer is preserved.)
    init?(balanceString: String, contract: String, role: AssetRole = .value) {
        let parts = balanceString.split(separator: " ")
        guard parts.count == 2, let amount = Decimal(string: String(parts[0])) else { return nil }
        let precision = String(parts[0]).split(separator: ".").last.map(\.count) ?? 0
        self.init(symbol: String(parts[1]), amount: amount, precision: precision,
                  contract: contract, role: role)
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
