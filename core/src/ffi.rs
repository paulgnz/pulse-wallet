//! C ABI for the Swift wallet (and any other native consumer).
//!
//! Strings are written into a caller-provided, NUL-terminated buffer. Each
//! function returns the number of bytes written (excluding the NUL), or -1 on
//! error (null pointer, buffer too small, or invalid input). PUB_R1 is ~57
//! chars and SIG_R1 ~101 chars, so a 256-byte buffer is always sufficient.

use crate::{assemble_sig_r1, decode_pvt_r1, encode_pub_r1};
use std::ffi::CStr;
use std::os::raw::{c_char, c_int};
use std::slice;

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
