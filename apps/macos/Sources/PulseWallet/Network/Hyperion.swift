import Foundation

/// Hyperion (v2) indexer client — used for token discovery and (later) history.
/// Reads remain valid while the chain is halted; responses carry the last
/// indexed block so the UI can show staleness.
struct Hyperion: Sendable {
    let endpoint: URL

    init?(_ string: String) {
        guard let url = URL(string: string) else { return nil }
        self.endpoint = url
    }

    struct TokenBalance: Decodable, Sendable {
        let symbol: String
        let precision: Int
        let amount: Double
        let contract: String
    }
    private struct TokensResponse: Decodable, Sendable {
        let tokens: [TokenBalance]
        let lastIndexedBlock: Int?
    }

    /// All token balances held by `account`, across every contract.
    func getTokens(_ account: String) async throws -> [TokenBalance] {
        var comps = URLComponents(url: endpoint.appendingPathComponent("v2/state/get_tokens"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "account", value: account)]
        var req = URLRequest(url: comps.url!, timeoutInterval: 15)
        req.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw PulseRPC.Failure(message: "Hyperion HTTP \(http.statusCode)")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(TokensResponse.self, from: data).tokens
    }
}

extension Asset {
    /// Build from a Hyperion token balance. SYS is the resource token; everything
    /// else is a value token.
    init(token: Hyperion.TokenBalance) {
        self.init(symbol: token.symbol,
                  amount: Decimal(token.amount),
                  precision: token.precision,
                  contract: token.contract,
                  role: token.symbol == "SYS" ? .resource : .value)
    }
}
