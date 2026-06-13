//! Antelope/PulseVM transaction serialization + signing digest.
//!
//! Signing digest = sha256( chain_id(32) ‖ packed_trx ‖ sha256(context_free_data) ).
//! With no context-free data, the trailing hash is sha256(<empty>).
//!
//! `build_transfer_signing` returns (packed_trx, preimage, digest):
//!  - R1 keys sign the PRE-IMAGE (CryptoKit/Enclave hash it with SHA-256 → digest)
//!  - K1 keys sign the DIGEST directly
//!  - assemble_sig_r1 needs the digest to derive the recovery id

use sha2::{Digest, Sha256};

fn sha256(data: &[u8]) -> [u8; 32] {
    let out = Sha256::digest(data);
    let mut r = [0u8; 32];
    r.copy_from_slice(&out);
    r
}

/// EOSIO/Antelope name (≤12 chars of [.a-z1-5]) → uint64.
pub fn name_to_u64(s: &str) -> u64 {
    fn char_value(c: u8) -> u64 {
        match c {
            b'a'..=b'z' => (c - b'a') as u64 + 6,
            b'1'..=b'5' => (c - b'1') as u64 + 1,
            _ => 0, // '.' and padding
        }
    }
    let bytes = s.as_bytes();
    let mut value: u64 = 0;
    for i in 0..13 {
        let c = if i < bytes.len() { char_value(bytes[i]) } else { 0 };
        if i < 12 {
            value |= (c & 0x1f) << (64 - 5 * (i + 1));
        } else {
            value |= c & 0x0f;
        }
    }
    value
}

fn write_varuint32(mut v: u32, out: &mut Vec<u8>) {
    loop {
        let mut b = (v & 0x7f) as u8;
        v >>= 7;
        if v != 0 {
            b |= 0x80;
        }
        out.push(b);
        if v == 0 {
            break;
        }
    }
}

/// Parse "1.0000 XPR" → (amount as integer units, precision, symbol).
fn parse_asset(qty: &str) -> Result<(i64, u8, String), String> {
    let parts: Vec<&str> = qty.split_whitespace().collect();
    if parts.len() != 2 {
        return Err("asset must be '<amount> <SYMBOL>'".into());
    }
    let amount_str = parts[0];
    let symbol = parts[1].to_string();
    let precision = amount_str.split('.').nth(1).map(|f| f.len()).unwrap_or(0) as u8;
    let digits: String = amount_str.chars().filter(|c| *c != '.').collect();
    let amount: i64 = digits.parse().map_err(|_| "bad amount".to_string())?;
    Ok((amount, precision, symbol))
}

fn serialize_asset(qty: &str, out: &mut Vec<u8>) -> Result<(), String> {
    let (amount, precision, symbol) = parse_asset(qty)?;
    out.extend_from_slice(&amount.to_le_bytes());
    out.push(precision);
    let sb = symbol.as_bytes();
    if sb.len() > 7 {
        return Err("symbol too long".into());
    }
    for i in 0..7 {
        out.push(if i < sb.len() { sb[i] } else { 0 });
    }
    Ok(())
}

fn serialize_transfer_data(from: &str, to: &str, qty: &str, memo: &str) -> Result<Vec<u8>, String> {
    let mut d = Vec::new();
    d.extend_from_slice(&name_to_u64(from).to_le_bytes());
    d.extend_from_slice(&name_to_u64(to).to_le_bytes());
    serialize_asset(qty, &mut d)?;
    write_varuint32(memo.len() as u32, &mut d);
    d.extend_from_slice(memo.as_bytes());
    Ok(d)
}

pub struct TransferParams<'a> {
    pub from: &'a str,
    pub to: &'a str,
    pub quantity: &'a str,
    pub memo: &'a str,
    pub contract: &'a str,   // token contract, e.g. "pulse.token"
    pub actor: &'a str,
    pub permission: &'a str, // e.g. "active"
    pub ref_block_num: u16,
    pub ref_block_prefix: u32,
    pub expiration: u32,     // unix seconds
}

/// Serialize a single-transfer transaction (no CFA, no extensions).
pub fn serialize_transfer_tx(p: &TransferParams) -> Result<Vec<u8>, String> {
    let mut t = Vec::new();
    t.extend_from_slice(&p.expiration.to_le_bytes());
    t.extend_from_slice(&p.ref_block_num.to_le_bytes());
    t.extend_from_slice(&p.ref_block_prefix.to_le_bytes());
    write_varuint32(0, &mut t); // max_net_usage_words
    t.push(0); // max_cpu_usage_ms
    write_varuint32(0, &mut t); // delay_sec
    write_varuint32(0, &mut t); // context_free_actions
    write_varuint32(1, &mut t); // actions
    t.extend_from_slice(&name_to_u64(p.contract).to_le_bytes());
    t.extend_from_slice(&name_to_u64("transfer").to_le_bytes());
    write_varuint32(1, &mut t); // authorization count
    t.extend_from_slice(&name_to_u64(p.actor).to_le_bytes());
    t.extend_from_slice(&name_to_u64(p.permission).to_le_bytes());
    let data = serialize_transfer_data(p.from, p.to, p.quantity, p.memo)?;
    write_varuint32(data.len() as u32, &mut t);
    t.extend_from_slice(&data);
    write_varuint32(0, &mut t); // transaction_extensions
    Ok(t)
}

/// (packed_trx, preimage, digest) for signing a transfer.
pub fn build_transfer_signing(
    p: &TransferParams,
    chain_id_hex: &str,
) -> Result<(Vec<u8>, Vec<u8>, Vec<u8>), String> {
    let chain_id = hex::decode(chain_id_hex).map_err(|e| e.to_string())?;
    if chain_id.len() != 32 {
        return Err("chain_id must be 32 bytes".into());
    }
    let packed = serialize_transfer_tx(p)?;
    let cfd_hash = sha256(&[]); // empty context-free data
    let mut preimage = Vec::with_capacity(32 + packed.len() + 32);
    preimage.extend_from_slice(&chain_id);
    preimage.extend_from_slice(&packed);
    preimage.extend_from_slice(&cfd_hash);
    let digest = sha256(&preimage);
    Ok((packed, preimage, digest.to_vec()))
}

#[cfg(test)]
mod tx_tests {
    use super::*;

    #[test]
    fn name_encoding_matches_known_values() {
        assert_eq!(name_to_u64("eosio"), 6138663577826885632);
        assert_eq!(name_to_u64("eosio.token"), 6138663591592764928);
        assert_eq!(name_to_u64(""), 0);
    }

    #[test]
    fn asset_serializes_to_16_bytes() {
        let mut out = Vec::new();
        serialize_asset("1.0000 XPR", &mut out).unwrap();
        assert_eq!(out.len(), 16);
        // amount 10000 little-endian
        assert_eq!(&out[0..8], &10000i64.to_le_bytes());
        assert_eq!(out[8], 4); // precision
        assert_eq!(&out[9..12], b"XPR");
    }

    #[test]
    fn transfer_digest_is_32_bytes_and_deterministic() {
        let p = TransferParams {
            from: "protonnz", to: "hello", quantity: "1.0000 XPR", memo: "hi",
            contract: "pulse.token", actor: "protonnz", permission: "active",
            ref_block_num: 0x0ade, ref_block_prefix: 0x12345678, expiration: 1_760_000_000,
        };
        let cid = "0d6f033e887fae475d641104b6e87762b6c869e87a101afeeb64d608ab376618";
        let (packed, preimage, digest) = build_transfer_signing(&p, cid).unwrap();
        assert!(!packed.is_empty());
        assert_eq!(preimage.len(), 32 + packed.len() + 32);
        assert_eq!(digest.len(), 32);
        // deterministic
        let (_, _, digest2) = build_transfer_signing(&p, cid).unwrap();
        assert_eq!(digest, digest2);
    }
}
