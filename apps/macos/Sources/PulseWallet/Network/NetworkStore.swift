import Foundation
import Observation

/// A configured PulseVM network the wallet can point at.
struct PulseNetwork: Identifiable, Codable, Hashable {
    var id: UUID
    var label: String
    var rpc: String
    var hyperion: String
    var explorer: String
    var chainId: String?
    var primarySymbol: String

    init(id: UUID = UUID(), label: String, rpc: String, hyperion: String,
         explorer: String = "", chainId: String? = nil, primarySymbol: String = "XPR") {
        self.id = id; self.label = label; self.rpc = rpc; self.hyperion = hyperion
        self.explorer = explorer; self.chainId = chainId; self.primarySymbol = primarySymbol
    }

    func accountURL(_ name: String) -> URL? {
        explorer.isEmpty ? nil : URL(string: "\(explorer)/account/\(name)")
    }
    func txURL(_ txid: String) -> URL? {
        explorer.isEmpty ? nil : URL(string: "\(explorer)/transaction/\(txid)")
    }
}

/// Persisted, ordered list of networks with a selected default. Users add, edit,
/// reorder, select, and delete networks from Settings.
@MainActor
@Observable
final class NetworkStore {
    private let key = "wallet.networks.v1"
    private let selKey = "wallet.networks.selected"

    private(set) var networks: [PulseNetwork]
    var selectedID: UUID { didSet { UserDefaults.standard.set(selectedID.uuidString, forKey: selKey) } }

    init() {
        let loaded: [PulseNetwork]
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([PulseNetwork].self, from: data), !saved.isEmpty {
            loaded = saved
        } else {
            loaded = NetworkStore.seed
        }
        var nets = loaded
        // Migration: ensure the XPR Network Pulse Testnet is present AND refreshed,
        // keyed by its STABLE id (its chain_id changes on every chain relaunch — PulseVM
        // derives it from the Avalanche blockchainID — so we refresh chainId in place
        // rather than appending a dead duplicate each rebuild).
        if let i = nets.firstIndex(where: { $0.id == NetworkStore.pulseTestnet.id }) {
            nets[i].rpc = NetworkStore.pulseTestnet.rpc
            nets[i].explorer = NetworkStore.pulseTestnet.explorer
            nets[i].hyperion = NetworkStore.pulseTestnet.hyperion
            nets[i].chainId = NetworkStore.pulseTestnet.chainId
        } else {
            nets.append(NetworkStore.pulseTestnet)
        }
        self.networks = nets
        if let s = UserDefaults.standard.string(forKey: selKey), let uid = UUID(uuidString: s),
           nets.contains(where: { $0.id == uid }) {
            self.selectedID = uid
        } else {
            self.selectedID = nets[0].id
        }
        persist()
    }

    /// Our self-hosted XPR Network Pulse Testnet (stable id → idempotent migration).
    static let pulseTestnet = PulseNetwork(
        id: UUID(uuidString: "2E5C9A10-0001-4000-8000-000000000001")!,
        label: "XPR Network Pulse Testnet",
        rpc: "https://rpc-testnet.pulsevm.dev",
        hyperion: "https://hyperion-testnet.pulsevm.dev",
        explorer: "https://testnet.explorer.pulsevm.dev",
        chainId: "25ca8f0ab74b88b13d861021989dc10193e3270a66bd70a15bca0615f9dc6bb2",
        primarySymbol: "XPR")

    static var seed: [PulseNetwork] {
        [PulseNetwork(
            label: "A-Chain Testnet",
            rpc: "https://rpc.a-chain-testnet.protonnz.com",
            hyperion: "https://hyperion.a-chain-testnet.protonnz.com",
            explorer: "https://a-chain-testnet.metalblockchain.org",
            chainId: "0d6f033e887fae475d641104b6e87762b6c869e87a101afeeb64d608ab376618",
            primarySymbol: "XPR"),
         pulseTestnet]
    }

    var active: PulseNetwork { networks.first { $0.id == selectedID } ?? networks[0] }

    private func persist() {
        if let data = try? JSONEncoder().encode(networks) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func add(_ network: PulseNetwork) { networks.append(network); persist() }

    func update(_ network: PulseNetwork) {
        guard let idx = networks.firstIndex(where: { $0.id == network.id }) else { return }
        networks[idx] = network; persist()
    }

    func delete(_ network: PulseNetwork) {
        guard networks.count > 1 else { return }   // keep at least one
        networks.removeAll { $0.id == network.id }
        if selectedID == network.id { selectedID = networks[0].id }
        persist()
    }

    func select(_ network: PulseNetwork) { selectedID = network.id }

    func move(_ network: PulseNetwork, by offset: Int) {
        guard let idx = networks.firstIndex(where: { $0.id == network.id }) else { return }
        let target = idx + offset
        guard networks.indices.contains(target) else { return }
        networks.swapAt(idx, target)
        persist()
    }
}
