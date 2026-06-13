//! C ABI for the Swift wallet (and any other native consumer).
//!
//! Strings are written into a caller-provided, NUL-terminated buffer. Each
//! function returns the number of bytes written (excluding the NUL), or -1 on
//! error (null pointer, buffer too small, or invalid input). PUB_R1 is ~57
//! chars and SIG_R1 ~101 chars, so a 256-byte buffer is always sufficient.

use crate::tx::{build_transfer_signing, TransferParams};
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
