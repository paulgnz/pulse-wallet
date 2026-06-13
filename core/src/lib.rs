//! PulseVM R1 (secp256r1) key & signature encoding for the wallet core.
//!
//! Ported from pulsevm-js (`src/crypto`, `src/base58.ts`). The Secure Enclave
//! produces a raw `r||s` ECDSA signature with no recovery id; PulseVM verifies
//! by RECOVERING the pubkey, so we must derive the recid here (CryptoKit can't).
//!
//! Formats:
//!  - PUB_R1 = "PUB_R1_" + base58( compressed_pubkey(33) ‖ ripemd160(pubkey‖"R1")[0..4] )
//!  - SIG_R1 = "SIG_R1_" + base58( [recid+31]‖r‖s (65) ‖ ripemd160(data‖"R1")[0..4] )
//!  - R1 enforces low-s only (no strict canonical), so Enclave sigs just need s-normalization.

use ecdsa::RecoveryId;
use p256::ecdsa::{Signature, VerifyingKey};
use ripemd::{Digest, Ripemd160};

pub mod ffi;

fn ripemd_checksum(data: &[u8], suffix: &[u8]) -> [u8; 4] {
    let mut h = Ripemd160::new();
    h.update(data);
    h.update(suffix);
    let out = h.finalize();
    [out[0], out[1], out[2], out[3]]
}

/// Encode a compressed secp256r1 public key (33 bytes) as a `PUB_R1_…` string.
pub fn encode_pub_r1(pub_compressed: &[u8; 33]) -> String {
    let mut data = pub_compressed.to_vec();
    data.extend_from_slice(&ripemd_checksum(pub_compressed, b"R1"));
    format!("PUB_R1_{}", bs58::encode(data).into_string())
}

/// Given a raw (r, s) signature over `digest` and the KNOWN signer pubkey
/// (compressed), normalize to low-s, derive the recovery id, and return a
/// PulseVM-acceptable `SIG_R1_…` string.
pub fn assemble_sig_r1(
    r: &[u8; 32],
    s: &[u8; 32],
    digest: &[u8; 32],
    pub_compressed: &[u8; 33],
) -> Result<String, String> {
    let mut rs = [0u8; 64];
    rs[..32].copy_from_slice(r);
    rs[32..].copy_from_slice(s);
    let sig = Signature::from_slice(&rs).map_err(|e| e.to_string())?;
    let sig_low = sig.normalize_s().unwrap_or(sig); // PulseVM/R1 wants low-s

    let mut found: Option<u8> = None;
    for rid in 0u8..4 {
        let recid = match RecoveryId::try_from(rid) {
            Ok(x) => x,
            Err(_) => continue,
        };
        if let Ok(vk) = VerifyingKey::recover_from_prehash(digest, &sig_low, recid) {
            if vk.to_encoded_point(true).as_bytes() == &pub_compressed[..] {
                found = Some(rid);
                break;
            }
        }
    }
    let rid = found.ok_or("could not derive recovery id (pubkey mismatch)")?;

    let sig_bytes = sig_low.to_bytes(); // 64 bytes, low-s
    let mut data = Vec::with_capacity(65 + 4);
    data.push(31 + rid); // Antelope header = recid + 31
    data.extend_from_slice(&sig_bytes);
    let cs = ripemd_checksum(&data, b"R1");
    data.extend_from_slice(&cs);
    Ok(format!("SIG_R1_{}", bs58::encode(data).into_string()))
}

#[cfg(test)]
mod tests {
    use super::*;
    // Vector generated with pulsevm-js (@metalblockchain/pulsevm-js).
    const DIGEST: &str = "ed2a1b6b8d301e1e79dfb10234fd9abbb094aedb43b3bf33449f9b8a1787e4e7";
    const R: &str = "605d020fed8d0517c4da5137522313cfa61ebc22629c3dd82c0af8478cb79235";
    const S: &str = "7279d68d5fc2c142becf1ec8b2e2c4cc71156bb260c544c7d534f7852d54bc8c";
    const PUBCOMP: &str = "021a361f4f1cec81197d74df3e2ab2ca964b7444912592a1df9be957f9e28521a8";
    const EXPECT_PUB: &str = "PUB_R1_562tX4UqQqJqfL3PnKFNYycVMQ1WghKDLzbx9XePwE1zSJj8Zo";
    const EXPECT_SIG: &str = "SIG_R1_KhMXY87g8FhNkm5BQAEkbt1avawEag8GbtyMZDGZEQPcJeWLkhTsaBpLHPPbRo5fc5D6FvzucatBaMAUbFZzcEz1yUmTpk";

    fn a32(h: &str) -> [u8; 32] { hex::decode(h).unwrap().try_into().unwrap() }
    fn a33(h: &str) -> [u8; 33] { hex::decode(h).unwrap().try_into().unwrap() }

    #[test]
    fn pub_r1_matches_pulsevm_js() {
        assert_eq!(encode_pub_r1(&a33(PUBCOMP)), EXPECT_PUB);
    }

    #[test]
    fn sig_r1_matches_pulsevm_js() {
        let got = assemble_sig_r1(&a32(R), &a32(S), &a32(DIGEST), &a33(PUBCOMP)).unwrap();
        assert_eq!(got, EXPECT_SIG);
    }
}
