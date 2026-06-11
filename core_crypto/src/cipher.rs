//! AES-256-GCM 字段加密（T1.2）。
//!
//! 密文 blob 格式（PDR 5.1）：`nonce(12B) || ciphertext || gcm_tag(16B)`，
//! 每次加密使用独立随机 96-bit nonce。
//!
//! AAD 规范（PDR 5.1 / T1.2）：`"{entry_id}:{field}"`，将密文绑定到
//! 条目与字段，防止密文跨字段/跨条目移植攻击。

use aes_gcm::aead::{Aead, Payload};
use aes_gcm::{Aes256Gcm, KeyInit, Nonce};

use crate::secret::SecretBytes;

/// AES-256 密钥长度。
pub const KEY_LEN: usize = 32;
/// GCM 标准 96-bit nonce。
pub const NONCE_LEN: usize = 12;
/// GCM 认证标签长度。
pub const TAG_LEN: usize = 16;

#[derive(Debug, thiserror::Error)]
pub enum CipherError {
    #[error("非法密钥长度（需 32 字节）")]
    InvalidKey,
    #[error("密文 blob 格式非法（长度不足 nonce+tag）")]
    Malformed,
    #[error("解密失败：密文或 AAD 被篡改，或密钥错误")]
    AuthFailed,
    #[error("系统随机源失败")]
    Rng,
}

/// 构造字段 AAD：`"{entry_id}:{field}"`。
pub fn field_aad(entry_id: &str, field: &str) -> Vec<u8> {
    format!("{entry_id}:{field}").into_bytes()
}

/// 加密：返回 `nonce || ciphertext || tag`。
pub fn seal(key: &SecretBytes, aad: &[u8], plaintext: &[u8]) -> Result<Vec<u8>, CipherError> {
    let cipher = Aes256Gcm::new_from_slice(key.expose()).map_err(|_| CipherError::InvalidKey)?;
    let mut nonce = [0u8; NONCE_LEN];
    getrandom::fill(&mut nonce).map_err(|_| CipherError::Rng)?;
    let ct_and_tag = cipher
        .encrypt(
            Nonce::from_slice(&nonce),
            Payload {
                msg: plaintext,
                aad,
            },
        )
        .map_err(|_| CipherError::AuthFailed)?;

    let mut blob = Vec::with_capacity(NONCE_LEN + ct_and_tag.len());
    blob.extend_from_slice(&nonce);
    blob.extend_from_slice(&ct_and_tag);
    Ok(blob)
}

/// 加密（nonce 由调用方提供并自行存放，返回 `ciphertext || tag`）。
///
/// 仅用于 nonce 需独立存放的场景（如库头 wrapped_dek，PDR 4.3）；
/// 调用方必须保证 nonce 为新鲜随机值，严禁复用。
pub fn seal_detached(
    key: &SecretBytes,
    nonce: &[u8; NONCE_LEN],
    aad: &[u8],
    plaintext: &[u8],
) -> Result<Vec<u8>, CipherError> {
    let cipher = Aes256Gcm::new_from_slice(key.expose()).map_err(|_| CipherError::InvalidKey)?;
    cipher
        .encrypt(
            Nonce::from_slice(nonce),
            Payload {
                msg: plaintext,
                aad,
            },
        )
        .map_err(|_| CipherError::AuthFailed)
}

/// [`seal_detached`] 的逆操作：解密 `ciphertext || tag`。
pub fn open_detached(
    key: &SecretBytes,
    nonce: &[u8],
    aad: &[u8],
    ct_and_tag: &[u8],
) -> Result<SecretBytes, CipherError> {
    if nonce.len() != NONCE_LEN || ct_and_tag.len() < TAG_LEN {
        return Err(CipherError::Malformed);
    }
    let cipher = Aes256Gcm::new_from_slice(key.expose()).map_err(|_| CipherError::InvalidKey)?;
    let plain = cipher
        .decrypt(
            Nonce::from_slice(nonce),
            Payload {
                msg: ct_and_tag,
                aad,
            },
        )
        .map_err(|_| CipherError::AuthFailed)?;
    Ok(SecretBytes::new(plain))
}

/// 解密 `nonce || ciphertext || tag`；任何篡改（含 AAD 不匹配）返回 [`CipherError::AuthFailed`]。
pub fn open(key: &SecretBytes, aad: &[u8], blob: &[u8]) -> Result<SecretBytes, CipherError> {
    if blob.len() < NONCE_LEN + TAG_LEN {
        return Err(CipherError::Malformed);
    }
    let cipher = Aes256Gcm::new_from_slice(key.expose()).map_err(|_| CipherError::InvalidKey)?;
    let (nonce, ct_and_tag) = blob.split_at(NONCE_LEN);
    let plain = cipher
        .decrypt(
            Nonce::from_slice(nonce),
            Payload {
                msg: ct_and_tag,
                aad,
            },
        )
        .map_err(|_| CipherError::AuthFailed)?;
    Ok(SecretBytes::new(plain))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn key(bytes: [u8; KEY_LEN]) -> SecretBytes {
        SecretBytes::new(bytes.to_vec())
    }

    /// 用固定 nonce 直接调底层 API 复现 NIST 向量（生产路径 seal 始终随机 nonce）。
    fn encrypt_fixed_nonce(key: &[u8], nonce: &[u8], aad: &[u8], pt: &[u8]) -> Vec<u8> {
        let cipher = Aes256Gcm::new_from_slice(key).unwrap();
        cipher
            .encrypt(Nonce::from_slice(nonce), Payload { msg: pt, aad })
            .unwrap()
    }

    /// NIST GCM 规范验证向量：AES-256、零密钥、零 IV、空明文 → 仅 tag。
    #[test]
    fn nist_aes256_gcm_empty_plaintext() {
        let out = encrypt_fixed_nonce(&[0u8; 32], &[0u8; 12], &[], &[]);
        assert_eq!(hex::encode(out), "530f8afbc74536b9a963b4f1c4cb738b");
    }

    /// NIST GCM 规范验证向量：AES-256、零密钥、零 IV、16B 零明文。
    #[test]
    fn nist_aes256_gcm_single_block() {
        let out = encrypt_fixed_nonce(&[0u8; 32], &[0u8; 12], &[], &[0u8; 16]);
        assert_eq!(
            hex::encode(out),
            concat!(
                "cea7403d4d606b6e074ec5d3baf39d18", // ciphertext
                "d0d1c8a799996bf0265b98b5d48ab919"  // tag
            )
        );
    }

    /// NIST CAVS gcmEncryptExtIV256（Keylen=256, IVlen=96, PTlen=128, AADlen=128）。
    #[test]
    fn nist_cavs_aes256_gcm_with_aad() {
        let key = hex::decode("92e11dcdaa866f5ce790fd24501f92509aacf4cb8b1339d50c9c1240935dd08b")
            .unwrap();
        let nonce = hex::decode("ac93a1a6145299bde902f21a").unwrap();
        let pt = hex::decode("2d71bcfa914e4ac045b2aa60955fad24").unwrap();
        let aad = hex::decode("1e0889016f67601c8ebea4943bc23ad6").unwrap();
        let out = encrypt_fixed_nonce(&key, &nonce, &aad, &pt);
        assert_eq!(
            hex::encode(out),
            concat!(
                "8995ae2e6df3dbf96fac7b7137bae67f", // ciphertext
                "eca5aa77d51d4a0a14d9c51e1da474ab"  // tag
            )
        );
    }

    #[test]
    fn seal_open_roundtrip() {
        let k = key([0x42; KEY_LEN]);
        let aad = field_aad("0198a3c4-id", "password");
        let blob = seal(&k, &aad, b"hunter2-secret").unwrap();
        assert_eq!(blob.len(), NONCE_LEN + 14 + TAG_LEN);
        let plain = open(&k, &aad, &blob).unwrap();
        assert_eq!(plain.expose(), b"hunter2-secret");
    }

    #[test]
    fn seal_uses_fresh_nonce_each_call() {
        let k = key([0x42; KEY_LEN]);
        let b1 = seal(&k, b"aad", b"same plaintext").unwrap();
        let b2 = seal(&k, b"aad", b"same plaintext").unwrap();
        assert_ne!(b1[..NONCE_LEN], b2[..NONCE_LEN], "nonce 不应重复");
        assert_ne!(b1, b2);
    }

    /// 验收核心：篡改 nonce / ct / tag / aad 任一字节均解密失败。
    #[test]
    fn any_single_byte_tamper_fails() {
        let k = key([0x42; KEY_LEN]);
        let aad = field_aad("entry-1", "notes");
        let blob = seal(&k, &aad, b"attack at dawn").unwrap();

        // 逐字节翻转整个 blob（覆盖 nonce、ct、tag 全部区域）
        for i in 0..blob.len() {
            let mut tampered = blob.clone();
            tampered[i] ^= 0x01;
            assert!(
                matches!(open(&k, &aad, &tampered), Err(CipherError::AuthFailed)),
                "blob 第 {i} 字节被篡改后仍解密成功"
            );
        }

        // AAD 逐字节翻转
        for i in 0..aad.len() {
            let mut bad_aad = aad.clone();
            bad_aad[i] ^= 0x01;
            assert!(
                matches!(open(&k, &bad_aad, &blob), Err(CipherError::AuthFailed)),
                "AAD 第 {i} 字节被篡改后仍解密成功"
            );
        }
    }

    /// AAD 绑定语义：同一密文不能移植到其他条目/字段。
    #[test]
    fn ciphertext_cannot_be_transplanted() {
        let k = key([0x42; KEY_LEN]);
        let blob = seal(&k, &field_aad("entry-1", "password"), b"pw").unwrap();
        assert!(open(&k, &field_aad("entry-2", "password"), &blob).is_err());
        assert!(open(&k, &field_aad("entry-1", "notes"), &blob).is_err());
    }

    #[test]
    fn wrong_key_fails() {
        let blob = seal(&key([0x42; KEY_LEN]), b"a", b"data").unwrap();
        assert!(matches!(
            open(&key([0x43; KEY_LEN]), b"a", &blob),
            Err(CipherError::AuthFailed)
        ));
    }

    #[test]
    fn malformed_blob_rejected() {
        let k = key([0x42; KEY_LEN]);
        assert!(matches!(
            open(&k, b"a", &[0u8; NONCE_LEN + TAG_LEN - 1]),
            Err(CipherError::Malformed)
        ));
        assert!(matches!(open(&k, b"a", &[]), Err(CipherError::Malformed)));
    }

    #[test]
    fn invalid_key_length_rejected() {
        let short = SecretBytes::new(vec![0u8; 16]);
        assert!(matches!(
            seal(&short, b"a", b"x"),
            Err(CipherError::InvalidKey)
        ));
    }

    #[test]
    fn empty_plaintext_roundtrip() {
        let k = key([0x01; KEY_LEN]);
        let aad = field_aad("e", "totp");
        let blob = seal(&k, &aad, b"").unwrap();
        assert_eq!(blob.len(), NONCE_LEN + TAG_LEN);
        assert_eq!(open(&k, &aad, &blob).unwrap().expose(), b"");
    }

    #[test]
    fn field_aad_format() {
        assert_eq!(field_aad("abc", "password"), b"abc:password".to_vec());
    }
}
