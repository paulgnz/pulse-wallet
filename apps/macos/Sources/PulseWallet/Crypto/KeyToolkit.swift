import Foundation
import CryptoKit

struct GeneratedKey: Sendable {
    let curve: WalletKey.Curve
    let publicKey: String
    let privateKey: String
    let raw: Data
}

/// Stateless key utilities: generate fresh keypairs and inspect/convert keys.
/// Pure crypto — no Enclave, no Keychain. (Generated keys are software keys.)
enum KeyToolkit {
    /// Generate a fresh software keypair on the chosen curve.
    static func generate(_ curve: WalletKey.Curve) -> GeneratedKey {
        let core = PulseCoreFFI()
        switch curve {
        case .r1:
            let pk = P256.Signing.PrivateKey()
            let raw = pk.rawRepresentation
            let pub = pk.publicKey.compressedRepresentation
            return GeneratedKey(curve: .r1,
                                publicKey: core.encodePubR1(compressedPublicKey: pub),
                                privateKey: core.encodePvtR1(raw), raw: raw)
        case .k1:
            let raw = core.generateK1()
            let pub = core.pubK1(privateKey: raw) ?? Data()
            return GeneratedKey(curve: .k1,
                                publicKey: core.encodePubK1(compressedPublicKey: pub),
                                privateKey: core.encodePvtK1(raw), raw: raw)
        }
    }

    /// Convert/inspect any key string → all derivable forms (label, value).
    static func inspect(_ input: String) -> [(String, String)] {
        let core = PulseCoreFFI()
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var out: [(String, String)] = []

        func r1(_ raw: Data) {
            guard raw.count == 32, let pk = try? P256.Signing.PrivateKey(rawRepresentation: raw) else { return }
            let pub = pk.publicKey.compressedRepresentation
            out += [("Curve", "R1 (secp256r1)"),
                    ("PUB_R1", core.encodePubR1(compressedPublicKey: pub)),
                    ("PVT_R1", core.encodePvtR1(raw)),
                    ("Public (hex)", pub.hexString),
                    ("Private (hex)", raw.hexString)]
        }
        func k1(_ raw: Data) {
            guard raw.count == 32, let pub = core.pubK1(privateKey: raw) else { return }
            out += [("Curve", "K1 (secp256k1)"),
                    ("PUB_K1", core.encodePubK1(compressedPublicKey: pub)),
                    ("PVT_K1", core.encodePvtK1(raw)),
                    ("Public (hex)", pub.hexString),
                    ("Private (hex)", raw.hexString)]
        }

        if t.hasPrefix("PVT_R1_"), let raw = core.decodePvtR1(t) {
            r1(raw)
        } else if (t.hasPrefix("PVT_K1_") || t.first == "5"), let raw = core.decodePvtK1(t) {
            k1(raw)
        } else if t.hasPrefix("PUB_R1_") || t.hasPrefix("PUB_K1_") {
            out += [("Type", "Public key (private not derivable)"), ("Public key", t)]
        } else if t.count == 64, let raw = Data(hexString: t) {
            out.append(("Input", "64-char hex — shown as both curves:"))
            r1(raw); k1(raw)
        } else if !t.isEmpty {
            out.append(("Error", "Unrecognized key format"))
        }
        return out
    }
}
