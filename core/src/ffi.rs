//! C ABI for the Swift wallet (and any other native consumer).
//!
//! Strings are written into a caller-provided, NUL-terminated buffer. Each
//! function returns the number of bytes written (excluding the NUL), or -1 on
//! error (null pointer, buffer too small, or invalid input). PUB_R1 is ~57
//! chars and SIG_R1 ~101 chars, so a 256-byte buffer is always sufficient.

use crate::tx::{
    build_msig_propose_transfer_signing, build_msig_signing, build_transfer_signing,
    msig_approve_data, msig_exec_data, parse_perm_levels, signing_material_hex, PermLevel,
    TransferParams,
};
use crate::{
    assemble_sig_r1, decode_pvt_k1, decode_pvt_r1, encode_pub_k1, encode_pub_r1, pub_k1_from_priv,
    sign_k1,
};
use std::ffi::CStr;
use std::os::raw::{c_char, c_int};
use std::slice;

/// Read a C string slice (None on null / invalid UTF-8).
unsafe fn cstr<'a>(p: *const c_char) -> Option<&'a str> {
    if p.is_null() {
        return None;
    }
    CStr::from_ptr(p).to_str().ok()
}

/// # Safety
/// `out` must point to at least `out_len` writable bytes.
unsafe fn write_str(out: *mut c_char, out_len: usize, s: &str) -> c_int {
    let bytes = s.as_bytes();
    if out.is_null() || bytes.len() + 1 > out_len {
        return -1;
    }
    let dst = slice::from_raw_parts_mut(out as *mut u8, out_len);
    dst[..bytes.len()].copy_from_slice(bytes);
    dst[bytes.len()] = 0; // NUL terminator
    bytes.len() as c_int
}

/// Encode a 33-byte compressed secp256r1 public key as `PUB_R1_…`.
///
/// # Safety
/// `pub33` must point to 33 readable bytes; `out` to `out_len` writable bytes.
#[no_mangle]
pub unsafe extern "C" fn pwc_encode_pub_r1(
    pub33: *const u8,
    out: *mut c_char,
    out_len: usize,
) -> c_int {
    if pub33.is_null() {
        return -1;
    }
    let mut arr = [0u8; 33];
    arr.copy_from_slice(slice::from_raw_parts(pub33, 33));
    write_str(out, out_len, &encode_pub_r1(&arr))
}

/// Assemble a `SIG_R1_…` from a raw `r‖s` (64B), the signed `digest` (32B), and
/// the known compressed signer pubkey (33B). Derives the recovery id internally.
///
/// # Safety
/// `rs64`/`digest32`/`pub33` must point to 64/32/33 readable bytes respectively;
/// `out` to `out_len` writable bytes.
#[no_mangle]
pub unsafe extern "C" fn pwc_assemble_sig_r1(
    rs64: *const u8,
    digest32: *const u8,
    pub33: *const u8,
    out: *mut c_char,
    out_len: usize,
) -> c_int {
    if rs64.is_null() || digest32.is_null() || pub33.is_null() {
        return -1;
    }
    let rs = slice::from_raw_parts(rs64, 64);
    let mut r = [0u8; 32];
    let mut s = [0u8; 32];
    r.copy_from_slice(&rs[..32]);
    s.copy_from_slice(&rs[32..]);
    let mut d = [0u8; 32];
    d.copy_from_slice(slice::from_raw_parts(digest32, 32));
    let mut p = [0u8; 33];
    p.copy_from_slice(slice::from_raw_parts(pub33, 33));

    match assemble_sig_r1(&r, &s, &d, &p) {
        Ok(sig) => write_str(out, out_len, &sig),
        Err(_) => -1,
    }
}

/// Decode a `PVT_R1_…` private-key string into 32 raw bytes (`out32`).
/// Returns 0 on success, -1 on bad prefix / base58 / checksum / length.
///
/// # Safety
/// `s` must be a valid NUL-terminated C string; `out32` must point to 32
/// writable bytes.
#[no_mangle]
pub unsafe extern "C" fn pwc_decode_pvt_r1(s: *const c_char, out32: *mut u8) -> c_int {
    if s.is_null() || out32.is_null() {
        return -1;
    }
    let text = match CStr::from_ptr(s).to_str() {
        Ok(t) => t,
        Err(_) => return -1,
    };
    match decode_pvt_r1(text) {
        Ok(key) => {
            slice::from_raw_parts_mut(out32, 32).copy_from_slice(&key);
            0
        }
        Err(_) => -1,
    }
}

// --- K1 (secp256k1) ---------------------------------------------------------

/// Decode a K1 private key ("PVT_K1_…" or legacy WIF) → 32 raw bytes.
/// Returns 0 on success, -1 on error.
///
/// # Safety
/// `s` is a NUL-terminated C string; `out32` points to 32 writable bytes.
#[no_mangle]
pub unsafe extern "C" fn pwc_decode_pvt_k1(s: *const c_char, out32: *mut u8) -> c_int {
    if s.is_null() || out32.is_null() {
        return -1;
    }
    let text = match CStr::from_ptr(s).to_str() {
        Ok(t) => t,
        Err(_) => return -1,
    };
    match decode_pvt_k1(text) {
        Ok(key) => {
            slice::from_raw_parts_mut(out32, 32).copy_from_slice(&key);
            0
        }
        Err(_) => -1,
    }
}

/// Derive the 33-byte compressed K1 public key from a raw private key.
///
/// # Safety
/// `priv32` points to 32 readable bytes; `out33` to 33 writable bytes.
#[no_mangle]
pub unsafe extern "C" fn pwc_pub_k1(priv32: *const u8, out33: *mut u8) -> c_int {
    if priv32.is_null() || out33.is_null() {
        return -1;
    }
    let mut p = [0u8; 32];
    p.copy_from_slice(slice::from_raw_parts(priv32, 32));
    match pub_k1_from_priv(&p) {
        Ok(pub_c) => {
            slice::from_raw_parts_mut(out33, 33).copy_from_slice(&pub_c);
            0
        }
        Err(_) => -1,
    }
}

/// Encode a 33-byte compressed K1 public key as "PUB_K1_…".
///
/// # Safety
/// `pub33` points to 33 readable bytes; `out` to `out_len` writable bytes.
#[no_mangle]
pub unsafe extern "C" fn pwc_encode_pub_k1(
    pub33: *const u8,
    out: *mut c_char,
    out_len: usize,
) -> c_int {
    if pub33.is_null() {
        return -1;
    }
    let mut arr = [0u8; 33];
    arr.copy_from_slice(slice::from_raw_parts(pub33, 33));
    write_str(out, out_len, &encode_pub_k1(&arr))
}

/// Sign a 32-byte digest with a K1 private key → "SIG_K1_…".
///
/// # Safety
/// `priv32`/`digest32` point to 32 readable bytes each; `out` to `out_len`
/// writable bytes.
#[no_mangle]
pub unsafe extern "C" fn pwc_sign_k1(
    priv32: *const u8,
    digest32: *const u8,
    out: *mut c_char,
    out_len: usize,
) -> c_int {
    if priv32.is_null() || digest32.is_null() {
        return -1;
    }
    let mut p = [0u8; 32];
    p.copy_from_slice(slice::from_raw_parts(priv32, 32));
    let mut d = [0u8; 32];
    d.copy_from_slice(slice::from_raw_parts(digest32, 32));
    match sign_k1(&p, &d) {
        Ok(sig) => write_str(out, out_len, &sig),
        Err(_) => -1,
    }
}

// --- Transaction building ---------------------------------------------------

/// Serialize a transfer + compute its signing material. Writes three hex lines
/// into `out`: "<packed_trx>\n<preimage>\n<digest>". Returns length or -1.
/// Use a 4096-byte buffer. Compute ref_block_num/prefix/expiration from getInfo.
///
/// # Safety
/// All string pointers are NUL-terminated C strings; `out` has `out_len` bytes.
#[no_mangle]
pub unsafe extern "C" fn pwc_build_transfer(
    from: *const c_char,
    to: *const c_char,
    quantity: *const c_char,
    memo: *const c_char,
    contract: *const c_char,
    actor: *const c_char,
    permission: *const c_char,
    chain_id_hex: *const c_char,
    ref_block_num: u16,
    ref_block_prefix: u32,
    expiration: u32,
    out: *mut c_char,
    out_len: usize,
) -> c_int {
    let fields = (
        cstr(from),
        cstr(to),
        cstr(quantity),
        cstr(memo),
        cstr(contract),
        cstr(actor),
        cstr(permission),
        cstr(chain_id_hex),
    );
    let (from, to, quantity, memo, contract, actor, permission, cid) = match fields {
        (Some(a), Some(b), Some(c), Some(d), Some(e), Some(f), Some(g), Some(h)) => {
            (a, b, c, d, e, f, g, h)
        }
        _ => return -1,
    };
    let params = TransferParams {
        from,
        to,
        quantity,
        memo,
        contract,
        actor,
        permission,
        ref_block_num,
        ref_block_prefix,
        expiration,
    };
    match build_transfer_signing(&params, cid) {
        Ok((packed, preimage, digest)) => {
            let s = format!(
                "{}\n{}\n{}",
                hex::encode(packed),
                hex::encode(preimage),
                hex::encode(digest)
            );
            write_str(out, out_len, &s)
        }
        Err(_) => -1,
    }
}

fn emit_tx(result: Result<(Vec<u8>, Vec<u8>, Vec<u8>), String>, out: *mut c_char, out_len: usize) -> c_int {
    match result {
        Ok((packed, preimage, digest)) => unsafe {
            let s = format!("{}\n{}\n{}", hex::encode(packed), hex::encode(preimage), hex::encode(digest));
            write_str(out, out_len, &s)
        },
        Err(_) => -1,
    }
}

/// Compute "(preimage)\n(digest)" (hex) for an externally-provided packed tx.
/// Used by the dapp signing transport (pulsevm://sign). Returns length or -1.
/// # Safety: `packed_hex`/`chain_id_hex` NUL-terminated; `out` has `out_len` bytes.
#[no_mangle]
pub unsafe extern "C" fn pwc_signing_material(
    packed_hex: *const c_char,
    chain_id_hex: *const c_char,
    out: *mut c_char,
    out_len: usize,
) -> c_int {
    let (packed, cid) = match (cstr(packed_hex), cstr(chain_id_hex)) {
        (Some(a), Some(b)) => (a, b),
        _ => return -1,
    };
    match signing_material_hex(packed, cid) {
        Ok((preimage, digest)) => {
            let s = format!("{}\n{}", hex::encode(preimage), hex::encode(digest));
            write_str(out, out_len, &s)
        }
        Err(_) => -1,
    }
}

// --- pulse.msig -------------------------------------------------------------

/// propose a single transfer. `requested` is "actor@perm;actor2@perm2".
/// # Safety: all string pointers are NUL-terminated; `out` has `out_len` bytes.
#[no_mangle]
pub unsafe extern "C" fn pwc_msig_propose_transfer(
    contract: *const c_char, proposer: *const c_char, proposal: *const c_char,
    requested: *const c_char, from: *const c_char, to: *const c_char,
    quantity: *const c_char, memo: *const c_char, token_contract: *const c_char,
    inner_expiration: u32, chain_id_hex: *const c_char,
    ref_block_num: u16, ref_block_prefix: u32, expiration: u32,
    out: *mut c_char, out_len: usize,
) -> c_int {
    let f = (cstr(contract), cstr(proposer), cstr(proposal), cstr(requested), cstr(from),
             cstr(to), cstr(quantity), cstr(memo), cstr(token_contract), cstr(chain_id_hex));
    let (contract, proposer, proposal, requested, from, to, quantity, memo, token, cid) = match f {
        (Some(a), Some(b), Some(c), Some(d), Some(e), Some(g), Some(h), Some(i), Some(j), Some(k)) =>
            (a, b, c, d, e, g, h, i, j, k),
        _ => return -1,
    };
    let inner = TransferParams {
        from, to, quantity, memo, contract: token, actor: proposer, permission: "active",
        ref_block_num, ref_block_prefix, expiration: inner_expiration,
    };
    let levels = parse_perm_levels(requested);
    emit_tx(build_msig_propose_transfer_signing(
        contract, proposer, proposal, &levels, &inner, cid, ref_block_num, ref_block_prefix, expiration),
        out, out_len)
}

/// approve a proposal (signed by `auth`).
/// # Safety: see above.
#[no_mangle]
pub unsafe extern "C" fn pwc_msig_approve(
    contract: *const c_char, proposer: *const c_char, proposal: *const c_char,
    level_actor: *const c_char, level_perm: *const c_char,
    auth_actor: *const c_char, auth_perm: *const c_char,
    chain_id_hex: *const c_char, ref_block_num: u16, ref_block_prefix: u32, expiration: u32,
    out: *mut c_char, out_len: usize,
) -> c_int {
    let f = (cstr(contract), cstr(proposer), cstr(proposal), cstr(level_actor),
             cstr(level_perm), cstr(auth_actor), cstr(auth_perm), cstr(chain_id_hex));
    let (contract, proposer, proposal, la, lp, aa, ap, cid) = match f {
        (Some(a), Some(b), Some(c), Some(d), Some(e), Some(g), Some(h), Some(i)) =>
            (a, b, c, d, e, g, h, i),
        _ => return -1,
    };
    let data = msig_approve_data(proposer, proposal,
        &PermLevel { actor: la.to_string(), permission: lp.to_string() });
    emit_tx(build_msig_signing(contract, "approve", data,
        PermLevel { actor: aa.to_string(), permission: ap.to_string() },
        cid, ref_block_num, ref_block_prefix, expiration), out, out_len)
}

/// exec a proposal (signed by `executer@active`).
/// # Safety: see above.
#[no_mangle]
pub unsafe extern "C" fn pwc_msig_exec(
    contract: *const c_char, proposer: *const c_char, proposal: *const c_char,
    executer: *const c_char, chain_id_hex: *const c_char,
    ref_block_num: u16, ref_block_prefix: u32, expiration: u32,
    out: *mut c_char, out_len: usize,
) -> c_int {
    let f = (cstr(contract), cstr(proposer), cstr(proposal), cstr(executer), cstr(chain_id_hex));
    let (contract, proposer, proposal, executer, cid) = match f {
        (Some(a), Some(b), Some(c), Some(d), Some(e)) => (a, b, c, d, e),
        _ => return -1,
    };
    let data = msig_exec_data(proposer, proposal, executer);
    emit_tx(build_msig_signing(contract, "exec", data,
        PermLevel { actor: executer.to_string(), permission: "active".to_string() },
        cid, ref_block_num, ref_block_prefix, expiration), out, out_len)
}
