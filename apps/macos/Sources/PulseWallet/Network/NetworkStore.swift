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
        // Migration: drop the retired XPR 1:1 demo network preset (its endpoints
        // went offline 2026-10-19), keyed by its stable id. If it was the only
        // saved network, fall back to the seed list.
        nets.removeAll { $0.id == NetworkStore.retiredDemoNetworkID }
        if nets.isEmpty { nets = NetworkStore.seed }
        self.networks = nets
        if let s = UserDefaults.standard.string(forKey: selKey), let uid = UUID(uuidString: s),
           nets.contains(where: { $0.id == uid }) {
            self.selectedID = uid
        } else {
            self.selectedID = nets[0].id
        }
        persist()
    }

    /// Stable id of the former "XPR 1:1 Testnet (Tahoe)" preset. That demo network
    /// was retired on 2026-10-19; XPR→PulseVM cutover testing is in progress and
    /// public test endpoints will be listed at https://pulsevm.dev/network/endpoints.
    static let retiredDemoNetworkID = UUID(uuidString: "2E5C9A10-0001-4000-8000-000000000001")!

    /// A-Chain Alpine (reset 2026-08-05). NOTE: Alpine resets frequently during
    /// consensus hardening — current endpoints/chain id live at
    /// https://pulsevm.dev/network/endpoints
    static var seed: [PulseNetwork] {
        [PulseNetwork(
            label: "A-Chain Alpine Testnet",
            rpc: "https://a-chain-alpine.metalblockchain.org/ext/bc/C6tuBzT2M3TZHyWc5Ro6L3cJyoxRAPy9avJeNh3FPzkBswXgX/rpc",
            hyperion: "https://a-chain-alpine-hyperion.metalblockchain.org",
            explorer: "https://a-chain-testnet.metalblockchain.org",
            chainId: "193526980f523c07a567dda80f5f543e2356518ce1475cf3e03d98ca740b3f67",
            primarySymbol: "XPR")]
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
