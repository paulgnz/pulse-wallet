// C ABI for pulse-wallet-core (Rust). Generated surface — see core/src/ffi.rs.
#ifndef PULSE_WALLET_CORE_H
#define PULSE_WALLET_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// pub33 (33B compressed P-256) -> "PUB_R1_…" into `out`.
// Returns bytes written (excl. NUL), or -1 on error.
int pwc_encode_pub_r1(const uint8_t *pub33, char *out, size_t out_len);

// rs64 (r‖s) + digest32 + pub33 -> "SIG_R1_…" into `out`.
// Derives the recovery id internally. Returns bytes written, or -1 on error.
int pwc_assemble_sig_r1(const uint8_t *rs64, const uint8_t *digest32,
                        const uint8_t *pub33, char *out, size_t out_len);

// "PVT_R1_…" -> 32 raw private-key bytes into out32. Returns 0 ok, -1 on error.
int pwc_decode_pvt_r1(const char *s, uint8_t *out32);

#ifdef __cplusplus
}
#endif

#endif // PULSE_WALLET_CORE_H
