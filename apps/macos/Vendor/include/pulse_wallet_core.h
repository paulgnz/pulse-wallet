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

// K1 (secp256k1) — for importing/controlling existing Antelope accounts.
int pwc_decode_pvt_k1(const char *s, uint8_t *out32);          // PVT_K1_/WIF -> raw32
int pwc_pub_k1(const uint8_t *priv32, uint8_t *out33);          // raw32 -> compressed pub
int pwc_encode_pub_k1(const uint8_t *pub33, char *out, size_t out_len); // -> "PUB_K1_…"
int pwc_sign_k1(const uint8_t *priv32, const uint8_t *digest32, char *out, size_t out_len);

// Serialize a transfer + signing material. Writes "<packed>\n<preimage>\n<digest>"
// (hex) into out. Use a 4096-byte buffer. Returns length or -1.
int pwc_build_transfer(const char *from, const char *to, const char *quantity,
                       const char *memo, const char *contract, const char *actor,
                       const char *permission, const char *chain_id_hex,
                       uint16_t ref_block_num, uint32_t ref_block_prefix, uint32_t expiration,
                       char *out, size_t out_len);

// Dapp transport: "<preimage>\n<digest>" (hex) for an external packed tx.
int pwc_signing_material(const char *packed_hex, const char *chain_id_hex, char *out, size_t out_len);

// updateauth: keys = "PUB_..@weight;PUB_..@weight". Writes packed/preimage/digest.
int pwc_build_updateauth(const char *system_contract, const char *account, const char *permission,
                         const char *parent, uint32_t threshold, const char *keys,
                         const char *auth_actor, const char *auth_perm, const char *chain_id_hex,
                         uint16_t ref_block_num, uint32_t ref_block_prefix, uint32_t expiration,
                         char *out, size_t out_len);

// pulse.msig. Each writes "<packed>\n<preimage>\n<digest>" (hex). 4096-byte buffer.
int pwc_msig_propose_transfer(const char *contract, const char *proposer, const char *proposal,
                              const char *requested, const char *from, const char *to,
                              const char *quantity, const char *memo, const char *token_contract,
                              uint32_t inner_expiration, const char *chain_id_hex,
                              uint16_t ref_block_num, uint32_t ref_block_prefix, uint32_t expiration,
                              char *out, size_t out_len);
int pwc_msig_approve(const char *contract, const char *proposer, const char *proposal,
                     const char *level_actor, const char *level_perm,
                     const char *auth_actor, const char *auth_perm, const char *chain_id_hex,
                     uint16_t ref_block_num, uint32_t ref_block_prefix, uint32_t expiration,
                     char *out, size_t out_len);
int pwc_msig_exec(const char *contract, const char *proposer, const char *proposal,
                  const char *executer, const char *chain_id_hex,
                  uint16_t ref_block_num, uint32_t ref_block_prefix, uint32_t expiration,
                  char *out, size_t out_len);

#ifdef __cplusplus
}
#endif

#endif // PULSE_WALLET_CORE_H
