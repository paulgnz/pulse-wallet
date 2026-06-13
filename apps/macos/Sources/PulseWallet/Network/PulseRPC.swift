import Foundation

// MARK: - Wire models (decoded from pulsevm.* JSON-RPC)

struct ChainInfo: Decodable, Sendable {
    let chainId: String
    let headBlockNum: Int
    let headBlockId: String
    let headBlockTime: String
    let headBlockProducer: String
    let lastIrreversibleBlockNum: Int
    let lastIrreversibleBlockId: String
    let serverVersion: String
}

struct ResLimit: Decodable, Sendable {
    let used: Int64
    let available: String   // chain returns these as strings
    let max: String

    var usedFraction: Double {
        guard let m = Double(max), m > 0 else { return 0 }
        return min(1, Double(used) / m)
    }
}

struct AuthKey: Decodable, Sendable { let key: String; let weight: Int }
struct RequiredAuth: Decodable, Sendable { let threshold: Int; let keys: [AuthKey] }
struct Permission: Decodable, Sendable {
    let permName: String
    let parent: String
    let requiredAuth: RequiredAuth
}

struct AccountInfo: Decodable, Sendable {
    let accountName: String
    let coreLiquidBalance: String?     // "1000.0000 SYS"
    let cpuWeight: Int64?
    let netWeight: Int64?
    let ramQuota: Int64
    let ramUsage: Int64
    let cpuLimit: ResLimit
    let netLimit: ResLimit
    let permissions: [Permission]

    /// Symbol of the chain's core/liquid token (SYS on A-Chain, XPR on mainnet).
    var coreSymbol: String? {
        coreLiquidBalance?.split(separator: " ").last.map(String.init)
    }
    var ramFraction: Double {
        guard ramQuota > 0 else { return 0 }
        return min(1, Double(ramUsage) / Double(ramQuota))
    }
}

// MARK: - JSON-RPC client

/// Thin async client for the PulseVM JSON-RPC endpoint (method `pulsevm.*`).
/// Read calls work even while the chain is halted (the node serves last state).
struct PulseRPC: Sendable {
    let endpoint: URL

    init?(_ string: String) {
        guard let url = URL(string: string) else { return nil }
        self.endpoint = url
    }

    struct Failure: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct Envelope<T: Decodable>: Decodable {
        let result: T?
        let error: RPCError?
    }
    private struct RPCError: Decodable { let code: Int; let message: String; let data: String? }

    func call<T: Decodable>(_ method: String,
                            params: [String: Any] = [:],
                            as type: T.Type) async throws -> T {
        var req = URLRequest(url: endpoint, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 1, "method": method, "params": params,
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw Failure(message: "HTTP \(http.statusCode)")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let env = try decoder.decode(Envelope<T>.self, from: data)
        if let e = env.error { throw Failure(message: e.data ?? e.message) }
        guard let result = env.result else { throw Failure(message: "empty result from \(method)") }
        return result
    }

    func getInfo() async throws -> ChainInfo {
        try await call("pulsevm.getInfo", as: ChainInfo.self)
    }

    func getAccount(_ name: String) async throws -> AccountInfo {
        try await call("pulsevm.getAccount", params: ["account_name": name], as: AccountInfo.self)
    }

    /// Returns balances like ["1000.0000 SYS"]; empty if the account holds none.
    func getCurrencyBalance(code: String, account: String, symbol: String) async throws -> [String] {
        try await call("pulsevm.getCurrencyBalance",
                       params: ["code": code, "account": account, "symbol": symbol],
                       as: [String].self)
    }

    /// Tolerates a bare-string result or a {transaction_id|id} object.
    struct TxResult: Decodable, Sendable {
        let txid: String
        init(from decoder: Decoder) throws {
            if let s = try? decoder.singleValueContainer().decode(String.self) { txid = s; return }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            txid = (try? c.decode(String.self, forKey: .transactionId))
                ?? (try? c.decode(String.self, forKey: .id)) ?? "submitted"
        }
        enum CodingKeys: String, CodingKey { case transactionId, id }
    }

    /// Submit a signed transaction. Returns the transaction id.
    func issueTx(signatures: [String], packedTrx: String) async throws -> String {
        let result: TxResult = try await call("pulsevm.issueTx", params: [
            "signatures": signatures,
            "compression": "none",
            "packed_context_free_data": "",
            "packed_trx": packedTrx,
        ], as: TxResult.self)
        return result.txid
    }
}
