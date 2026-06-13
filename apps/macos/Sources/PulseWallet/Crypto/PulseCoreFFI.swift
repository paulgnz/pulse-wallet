import Foundation

/// Real `PulseCore`, backed by the Rust crate `pulse-wallet-core` through its C
/// ABI (see Vendor/). `encodePubR1` / `assembleSigR1` are validated byte-for-byte
/// against pulsevm-js, so the signature this produces is exactly what the chain
/// accepts. `transferDigest` lands when the serializer is ported into the core.
struct PulseCoreFFI: PulseCore {

    func encodePubR1(compressedPublicKey: Data) -> String {
        guard compressedPublicKey.count == 33 else { return "" }
        var out = [CChar](repeating: 0, count: 256)
        let n = compressedPublicKey.withUnsafeBytes { pk in
            pwc_encode_pub_r1(pk.bindMemory(to: UInt8.self).baseAddress, &out, out.count)
        }
        return n >= 0 ? String(cString: out) : ""
    }

    func assembleSigR1(rs: Data, digest: Data, compressedPublicKey: Data) throws -> String {
        guard rs.count == 64 else { throw PulseCoreError.badInput("rs must be 64 bytes") }
        guard digest.count == 32 else { throw PulseCoreError.badInput("digest must be 32 bytes") }
        guard compressedPublicKey.count == 33 else { throw PulseCoreError.badInput("pubkey must be 33 bytes") }

        var out = [CChar](repeating: 0, count: 256)
        let n = rs.withUnsafeBytes { rsp in
            digest.withUnsafeBytes { dp in
                compressedPublicKey.withUnsafeBytes { pp in
                    pwc_assemble_sig_r1(
                        rsp.bindMemory(to: UInt8.self).baseAddress,
                        dp.bindMemory(to: UInt8.self).baseAddress,
                        pp.bindMemory(to: UInt8.self).baseAddress,
                        &out, out.count)
                }
            }
        }
        guard n >= 0 else {
            throw PulseCoreError.signing("could not derive recovery id / assemble SIG_R1")
        }
        return String(cString: out)
    }

    func decodePvtR1(_ wif: String) -> Data? {
        var out = [UInt8](repeating: 0, count: 32)
        let ok = wif.withCString { pwc_decode_pvt_r1($0, &out) }
        return ok == 0 ? Data(out) : nil
    }

    func decodePvtK1(_ wif: String) -> Data? {
        var out = [UInt8](repeating: 0, count: 32)
        let ok = wif.withCString { pwc_decode_pvt_k1($0, &out) }
        return ok == 0 ? Data(out) : nil
    }

    func pubK1(privateKey: Data) -> Data? {
        guard privateKey.count == 32 else { return nil }
        var out = [UInt8](repeating: 0, count: 33)
        let ok = privateKey.withUnsafeBytes { p in
            pwc_pub_k1(p.bindMemory(to: UInt8.self).baseAddress, &out)
        }
        return ok == 0 ? Data(out) : nil
    }

    func encodePubK1(compressedPublicKey: Data) -> String {
        guard compressedPublicKey.count == 33 else { return "" }
        var out = [CChar](repeating: 0, count: 256)
        let n = compressedPublicKey.withUnsafeBytes { pk in
            pwc_encode_pub_k1(pk.bindMemory(to: UInt8.self).baseAddress, &out, out.count)
        }
        return n >= 0 ? String(cString: out) : ""
    }

    func signK1(privateKey: Data, digest: Data) throws -> String {
        guard privateKey.count == 32 else { throw PulseCoreError.badInput("priv must be 32 bytes") }
        guard digest.count == 32 else { throw PulseCoreError.badInput("digest must be 32 bytes") }
        var out = [CChar](repeating: 0, count: 256)
        let n = privateKey.withUnsafeBytes { p in
            digest.withUnsafeBytes { d in
                pwc_sign_k1(p.bindMemory(to: UInt8.self).baseAddress,
                            d.bindMemory(to: UInt8.self).baseAddress, &out, out.count)
            }
        }
        guard n >= 0 else { throw PulseCoreError.signing("K1 signing failed") }
        return String(cString: out)
    }

    func transferDigest(from: String, to: String, quantity: String,
                        memo: String, chainID: String) throws -> (preImage: Data, digest: Data) {
        throw PulseCoreError.notImplemented("transferDigest — port serializer into pulse-wallet-core")
    }
}
