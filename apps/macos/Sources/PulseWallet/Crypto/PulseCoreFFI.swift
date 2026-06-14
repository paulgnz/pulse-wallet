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

    func encodePvtR1(_ raw: Data) -> String {
        guard raw.count == 32 else { return "" }
        var out = [CChar](repeating: 0, count: 128)
        let n = raw.withUnsafeBytes { pwc_encode_pvt_r1($0.bindMemory(to: UInt8.self).baseAddress, &out, out.count) }
        return n >= 0 ? String(cString: out) : ""
    }

    func decodePvtK1(_ wif: String) -> Data? {
        var out = [UInt8](repeating: 0, count: 32)
        let ok = wif.withCString { pwc_decode_pvt_k1($0, &out) }
        return ok == 0 ? Data(out) : nil
    }

    func encodePvtK1(_ raw: Data) -> String {
        guard raw.count == 32 else { return "" }
        var out = [CChar](repeating: 0, count: 128)
        let n = raw.withUnsafeBytes { pwc_encode_pvt_k1($0.bindMemory(to: UInt8.self).baseAddress, &out, out.count) }
        return n >= 0 ? String(cString: out) : ""
    }

    func generateK1() -> Data {
        var out = [UInt8](repeating: 0, count: 32)
        return pwc_generate_k1(&out) == 0 ? Data(out) : Data()
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

    private func parse(_ out: [CChar], _ n: Int32, _ what: String) throws -> BuiltTx {
        guard n >= 0 else { throw PulseCoreError.signing("\(what) failed (bad params?)") }
        let parts = String(cString: out).split(separator: "\n", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw PulseCoreError.signing("malformed tx output") }
        return BuiltTx(packed: String(parts[0]), preimage: String(parts[1]), digest: String(parts[2]))
    }

    func buildTransfer(from: String, to: String, quantity: String, memo: String,
                       contract: String, actor: String, permission: String,
                       chainId: String, refBlockNum: UInt16, refBlockPrefix: UInt32,
                       expiration: UInt32) throws -> BuiltTx {
        var out = [CChar](repeating: 0, count: 4096)
        let n = pwc_build_transfer(from, to, quantity, memo, contract, actor, permission,
                                   chainId, refBlockNum, refBlockPrefix, expiration, &out, out.count)
        return try parse(out, n, "buildTransfer")
    }

    func msigProposeTransfer(contract: String, proposer: String, proposal: String,
                             requested: String, from: String, to: String, quantity: String,
                             memo: String, tokenContract: String, innerExpiration: UInt32,
                             chainId: String, refBlockNum: UInt16, refBlockPrefix: UInt32,
                             expiration: UInt32) throws -> BuiltTx {
        var out = [CChar](repeating: 0, count: 4096)
        let n = pwc_msig_propose_transfer(contract, proposer, proposal, requested, from, to,
                                          quantity, memo, tokenContract, innerExpiration, chainId,
                                          refBlockNum, refBlockPrefix, expiration, &out, out.count)
        return try parse(out, n, "msigProposeTransfer")
    }

    func msigApprove(contract: String, proposer: String, proposal: String,
                     levelActor: String, levelPerm: String, authActor: String, authPerm: String,
                     chainId: String, refBlockNum: UInt16, refBlockPrefix: UInt32,
                     expiration: UInt32) throws -> BuiltTx {
        var out = [CChar](repeating: 0, count: 4096)
        let n = pwc_msig_approve(contract, proposer, proposal, levelActor, levelPerm,
                                 authActor, authPerm, chainId, refBlockNum, refBlockPrefix,
                                 expiration, &out, out.count)
        return try parse(out, n, "msigApprove")
    }

    func msigExec(contract: String, proposer: String, proposal: String, executer: String,
                  chainId: String, refBlockNum: UInt16, refBlockPrefix: UInt32,
                  expiration: UInt32) throws -> BuiltTx {
        var out = [CChar](repeating: 0, count: 4096)
        let n = pwc_msig_exec(contract, proposer, proposal, executer, chainId,
                              refBlockNum, refBlockPrefix, expiration, &out, out.count)
        return try parse(out, n, "msigExec")
    }

    func buildStake(contract: String, from: String, receiver: String, netQty: String, cpuQty: String,
                    transfer: Bool, chainId: String, refBlockNum: UInt16, refBlockPrefix: UInt32,
                    expiration: UInt32) throws -> BuiltTx {
        var out = [CChar](repeating: 0, count: 4096)
        let n = pwc_build_stake(contract, from, receiver, netQty, cpuQty, transfer ? 1 : 0,
                                chainId, refBlockNum, refBlockPrefix, expiration, &out, out.count)
        return try parse(out, n, "buildStake")
    }
    func buildUnstake(contract: String, from: String, receiver: String, netQty: String, cpuQty: String,
                      chainId: String, refBlockNum: UInt16, refBlockPrefix: UInt32,
                      expiration: UInt32) throws -> BuiltTx {
        var out = [CChar](repeating: 0, count: 4096)
        let n = pwc_build_unstake(contract, from, receiver, netQty, cpuQty,
                                  chainId, refBlockNum, refBlockPrefix, expiration, &out, out.count)
        return try parse(out, n, "buildUnstake")
    }
    func buildRefund(contract: String, owner: String, chainId: String, refBlockNum: UInt16,
                     refBlockPrefix: UInt32, expiration: UInt32) throws -> BuiltTx {
        var out = [CChar](repeating: 0, count: 4096)
        let n = pwc_build_refund(contract, owner, chainId, refBlockNum, refBlockPrefix, expiration, &out, out.count)
        return try parse(out, n, "buildRefund")
    }

    func signingMaterial(packedTrx: String, chainId: String) throws -> (preimage: String, digest: String) {
        var out = [CChar](repeating: 0, count: 16384)
        let n = pwc_signing_material(packedTrx, chainId, &out, out.count)
        guard n >= 0 else { throw PulseCoreError.signing("signingMaterial failed") }
        let parts = String(cString: out).split(separator: "\n", omittingEmptySubsequences: false)
        guard parts.count == 2 else { throw PulseCoreError.signing("malformed material") }
        return (String(parts[0]), String(parts[1]))
    }

    func buildUpdateAuth(systemContract: String, account: String, permission: String,
                         parent: String, threshold: UInt32, keys: String,
                         authActor: String, authPerm: String, chainId: String,
                         refBlockNum: UInt16, refBlockPrefix: UInt32, expiration: UInt32) throws -> BuiltTx {
        var out = [CChar](repeating: 0, count: 8192)
        let n = pwc_build_updateauth(systemContract, account, permission, parent, threshold, keys,
                                     authActor, authPerm, chainId, refBlockNum, refBlockPrefix,
                                     expiration, &out, out.count)
        return try parse(out, n, "buildUpdateAuth")
    }

    func buildUpdateAuthFull(systemContract: String, account: String, permission: String,
                             parent: String, threshold: UInt32, keys: String, accounts: String, waits: String,
                             authActor: String, authPerm: String, chainId: String,
                             refBlockNum: UInt16, refBlockPrefix: UInt32, expiration: UInt32) throws -> BuiltTx {
        var out = [CChar](repeating: 0, count: 16384)
        let n = pwc_build_updateauth_full(systemContract, account, permission, parent, threshold,
                                          keys, accounts, waits, authActor, authPerm, chainId,
                                          refBlockNum, refBlockPrefix, expiration, &out, out.count)
        return try parse(out, n, "buildUpdateAuthFull")
    }

    func buildLinkAuth(systemContract: String, account: String, code: String, type: String,
                       requirement: String, authActor: String, authPerm: String, chainId: String,
                       refBlockNum: UInt16, refBlockPrefix: UInt32, expiration: UInt32) throws -> BuiltTx {
        var out = [CChar](repeating: 0, count: 8192)
        let n = pwc_build_linkauth(systemContract, account, code, type, requirement,
                                   authActor, authPerm, chainId, refBlockNum, refBlockPrefix,
                                   expiration, &out, out.count)
        return try parse(out, n, "buildLinkAuth")
    }

    func buildUnlinkAuth(systemContract: String, account: String, code: String, type: String,
                         authActor: String, authPerm: String, chainId: String,
                         refBlockNum: UInt16, refBlockPrefix: UInt32, expiration: UInt32) throws -> BuiltTx {
        var out = [CChar](repeating: 0, count: 8192)
        let n = pwc_build_unlinkauth(systemContract, account, code, type,
                                     authActor, authPerm, chainId, refBlockNum, refBlockPrefix,
                                     expiration, &out, out.count)
        return try parse(out, n, "buildUnlinkAuth")
    }

    func buildDeleteAuth(systemContract: String, account: String, permission: String,
                         authActor: String, authPerm: String, chainId: String,
                         refBlockNum: UInt16, refBlockPrefix: UInt32, expiration: UInt32) throws -> BuiltTx {
        var out = [CChar](repeating: 0, count: 8192)
        let n = pwc_build_deleteauth(systemContract, account, permission,
                                     authActor, authPerm, chainId, refBlockNum, refBlockPrefix,
                                     expiration, &out, out.count)
        return try parse(out, n, "buildDeleteAuth")
    }

    func decodeTransaction(packedTrx: String) -> DecodedTx? {
        var out = [CChar](repeating: 0, count: 16384)
        let n = pwc_decode_transaction(packedTrx, &out, out.count)
        guard n >= 0, let data = String(cString: out).data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(DecodedTx.self, from: data)
    }
}
