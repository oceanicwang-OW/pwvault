//! 库文件容器格式（T1.3，PDR 4.3 v0.4 定稿）。
//!
//! ```text
//! ┌─────────────────────────────────────────────┐
//! │ magic "PWVAULT1" (8B) + header_len (u32 LE) │
//! │ Header (明文 JSON)：version / kdf /          │
//! │   dek_nonce / wrapped_dek                   │
//! ├─────────────────────────────────────────────┤
//! │ Body: SQLite 序列化镜像（T1.5 起使用）        │
//! ├─────────────────────────────────────────────┤
//! │ Trailer: BLAKE3 校验和 32B（损坏检测，非防篡改）│
//! └─────────────────────────────────────────────┘
//! ```
//!
//! 防篡改不靠 Trailer（攻击者可重算），靠 wrapped_dek 的 AAD 绑定：
//! AAD = Header 除 wrapped_dek 外字段的规范化 JSON（字段按结构体声明序，
//! 序作为格式的一部分不可变更）。Header 任一字段被改 → DEK 解包失败
//! [`VaultFormatError::HeaderTampered`]，同时天然防 KDF 参数降级攻击。

use serde::{Deserialize, Serialize};

use crate::cipher::{self, CipherError, NONCE_LEN};
use crate::kdf::KdfParams;
use crate::secret::SecretBytes;

pub const MAGIC: &[u8; 8] = b"PWVAULT1";
pub const FORMAT_VERSION: u32 = 1;
const HEADER_LEN_SIZE: usize = 4;
const CHECKSUM_LEN: usize = 32;
/// Header JSON 长度上限（防异常值导致的越界/内存放大）。
const MAX_HEADER_LEN: usize = 64 * 1024;

/// 库头（明文 JSON）。字段声明顺序即序列化顺序，是格式的一部分。
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct VaultHeader {
    pub version: u32,
    pub kdf: KdfParams,
    #[serde(with = "crate::b64")]
    pub dek_nonce: Vec<u8>,
    #[serde(with = "crate::b64")]
    pub wrapped_dek: Vec<u8>,
}

/// 解码后的容器。
#[derive(Debug, PartialEq)]
pub struct VaultFile {
    pub header: VaultHeader,
    pub body: Vec<u8>,
}

#[derive(Debug, thiserror::Error)]
pub enum VaultFormatError {
    #[error("不是 PwVault 库文件（magic 不符）")]
    BadMagic,
    #[error("库文件格式版本不支持: {0}")]
    UnsupportedVersion(u32),
    #[error("库文件损坏（校验和不符或结构非法），请从 backups/ 恢复")]
    Corrupted,
    #[error("库头被篡改或密钥不符（DEK 解包失败）")]
    HeaderTampered,
    #[error("系统随机源失败")]
    Rng,
    #[error("加密原语错误: {0}")]
    Cipher(#[from] CipherError),
}

/// wrapped_dek 的 AAD：Header 除 wrapped_dek 外的字段，规范化 JSON。
fn header_aad(version: u32, kdf: &KdfParams, dek_nonce: &[u8]) -> Vec<u8> {
    #[derive(Serialize)]
    struct HeaderAad<'a> {
        version: u32,
        kdf: &'a KdfParams,
        #[serde(with = "crate::b64")]
        dek_nonce: &'a [u8],
    }
    serde_json::to_vec(&HeaderAad {
        version,
        kdf,
        dek_nonce,
    })
    .expect("header AAD 序列化不应失败")
}

/// 用 KEK 包裹 DEK，生成完整库头（建库 / 改密时调用，nonce 每次新随机）。
pub fn make_header(
    kek: &SecretBytes,
    dek: &SecretBytes,
    kdf: KdfParams,
) -> Result<VaultHeader, VaultFormatError> {
    let mut nonce = [0u8; NONCE_LEN];
    getrandom::fill(&mut nonce).map_err(|_| VaultFormatError::Rng)?;
    let aad = header_aad(FORMAT_VERSION, &kdf, &nonce);
    let wrapped = cipher::seal_detached(kek, &nonce, &aad, dek.expose())?;
    Ok(VaultHeader {
        version: FORMAT_VERSION,
        kdf,
        dek_nonce: nonce.to_vec(),
        wrapped_dek: wrapped,
    })
}

/// 用 KEK 解包 DEK。失败即库头被篡改或 KEK 不符
/// （解锁路径由 T1.4 映射为 ErrWrongPassword）。
pub fn unwrap_dek(
    kek: &SecretBytes,
    header: &VaultHeader,
) -> Result<SecretBytes, VaultFormatError> {
    let aad = header_aad(header.version, &header.kdf, &header.dek_nonce);
    cipher::open_detached(kek, &header.dek_nonce, &aad, &header.wrapped_dek)
        .map_err(|_| VaultFormatError::HeaderTampered)
}

/// 编码容器：`magic ‖ header_len ‖ header_json ‖ body ‖ blake3`。
pub fn encode(header: &VaultHeader, body: &[u8]) -> Result<Vec<u8>, VaultFormatError> {
    let json = serde_json::to_vec(header).map_err(|_| VaultFormatError::Corrupted)?;
    debug_assert!(json.len() <= MAX_HEADER_LEN);
    let mut out =
        Vec::with_capacity(MAGIC.len() + HEADER_LEN_SIZE + json.len() + body.len() + CHECKSUM_LEN);
    out.extend_from_slice(MAGIC);
    out.extend_from_slice(&(json.len() as u32).to_le_bytes());
    out.extend_from_slice(&json);
    out.extend_from_slice(body);
    let checksum = blake3::hash(&out);
    out.extend_from_slice(checksum.as_bytes());
    Ok(out)
}

/// 解码容器。校验顺序：magic → Trailer 校验和 → header_len 边界 →
/// Header JSON → version（PDR 4.3 解锁流程）。
pub fn decode(bytes: &[u8]) -> Result<VaultFile, VaultFormatError> {
    let min_len = MAGIC.len() + HEADER_LEN_SIZE + CHECKSUM_LEN;
    if bytes.len() < min_len {
        return Err(VaultFormatError::Corrupted);
    }
    if &bytes[..MAGIC.len()] != MAGIC {
        return Err(VaultFormatError::BadMagic);
    }

    let (payload, trailer) = bytes.split_at(bytes.len() - CHECKSUM_LEN);
    if blake3::hash(payload).as_bytes() != trailer {
        return Err(VaultFormatError::Corrupted);
    }

    let header_len = u32::from_le_bytes(
        bytes[MAGIC.len()..MAGIC.len() + HEADER_LEN_SIZE]
            .try_into()
            .expect("固定 4 字节"),
    ) as usize;
    let header_start = MAGIC.len() + HEADER_LEN_SIZE;
    if header_len > MAX_HEADER_LEN || header_start + header_len > payload.len() {
        return Err(VaultFormatError::Corrupted);
    }

    let header: VaultHeader =
        serde_json::from_slice(&payload[header_start..header_start + header_len])
            .map_err(|_| VaultFormatError::Corrupted)?;
    if header.version != FORMAT_VERSION {
        return Err(VaultFormatError::UnsupportedVersion(header.version));
    }

    Ok(VaultFile {
        header,
        body: payload[header_start + header_len..].to_vec(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::kdf::SALT_LEN;

    fn test_kdf() -> KdfParams {
        KdfParams {
            algo: "argon2id".into(),
            salt: vec![0x11; SALT_LEN],
            m_kib: 1024,
            t_cost: 1,
            p_lanes: 4,
        }
    }

    fn kek() -> SecretBytes {
        SecretBytes::new(vec![0x42; 32])
    }

    fn dek() -> SecretBytes {
        SecretBytes::new(vec![0x99; 32])
    }

    fn sample_container() -> (VaultHeader, Vec<u8>) {
        let header = make_header(&kek(), &dek(), test_kdf()).unwrap();
        let body = b"sqlite image placeholder".to_vec();
        (header, body)
    }

    #[test]
    fn encode_decode_roundtrip() {
        let (header, body) = sample_container();
        let bytes = encode(&header, &body).unwrap();
        let file = decode(&bytes).unwrap();
        assert_eq!(file.header, header);
        assert_eq!(file.body, body);
    }

    #[test]
    fn empty_body_roundtrip() {
        let (header, _) = sample_container();
        let bytes = encode(&header, &[]).unwrap();
        assert_eq!(decode(&bytes).unwrap().body, Vec::<u8>::new());
    }

    #[test]
    fn wrap_unwrap_dek_roundtrip() {
        let header = make_header(&kek(), &dek(), test_kdf()).unwrap();
        let recovered = unwrap_dek(&kek(), &header).unwrap();
        assert_eq!(recovered.expose(), dek().expose());
    }

    #[test]
    fn bad_magic_rejected() {
        let (header, body) = sample_container();
        let mut bytes = encode(&header, &body).unwrap();
        bytes[0] ^= 0x01;
        assert!(matches!(decode(&bytes), Err(VaultFormatError::BadMagic)));
    }

    #[test]
    fn unsupported_version_reported() {
        let (mut header, body) = sample_container();
        header.version = 99;
        let bytes = encode(&header, &body).unwrap();
        assert!(matches!(
            decode(&bytes),
            Err(VaultFormatError::UnsupportedVersion(99))
        ));
    }

    #[test]
    fn truncated_file_is_corrupted() {
        let (header, body) = sample_container();
        let bytes = encode(&header, &body).unwrap();
        assert!(matches!(
            decode(&bytes[..bytes.len() - 1]),
            Err(VaultFormatError::Corrupted)
        ));
        assert!(matches!(decode(&[]), Err(VaultFormatError::Corrupted)));
    }

    /// 验收：Trailer 不符报 Corrupted——payload（magic 之外）或 trailer
    /// 任一字节翻转都应被校验和拦截。
    #[test]
    fn any_payload_or_trailer_flip_is_corrupted() {
        let (header, body) = sample_container();
        let bytes = encode(&header, &body).unwrap();
        for i in MAGIC.len()..bytes.len() {
            let mut t = bytes.clone();
            t[i] ^= 0x01;
            assert!(
                matches!(decode(&t), Err(VaultFormatError::Corrupted)),
                "第 {i} 字节翻转未被检出"
            );
        }
    }

    /// 验收：Header 被改 1 字节（攻击者重算校验和，骗过 Trailer）→
    /// DEK 解包失败报 HeaderTampered。逐字段验证 AAD 绑定。
    #[test]
    fn tampered_header_fails_dek_unwrap() {
        let header = make_header(&kek(), &dek(), test_kdf()).unwrap();

        let mut t = header.clone();
        t.kdf.salt[0] ^= 0x01;
        assert!(matches!(
            unwrap_dek(&kek(), &t),
            Err(VaultFormatError::HeaderTampered)
        ));

        let mut t = header.clone();
        t.kdf.m_kib = 8; // KDF 降级攻击
        assert!(matches!(
            unwrap_dek(&kek(), &t),
            Err(VaultFormatError::HeaderTampered)
        ));

        let mut t = header.clone();
        t.dek_nonce[0] ^= 0x01;
        assert!(matches!(
            unwrap_dek(&kek(), &t),
            Err(VaultFormatError::HeaderTampered)
        ));

        let mut t = header.clone();
        t.wrapped_dek[0] ^= 0x01;
        assert!(matches!(
            unwrap_dek(&kek(), &t),
            Err(VaultFormatError::HeaderTampered)
        ));
    }

    #[test]
    fn wrong_kek_fails_unwrap() {
        let header = make_header(&kek(), &dek(), test_kdf()).unwrap();
        let wrong = SecretBytes::new(vec![0x43; 32]);
        assert!(matches!(
            unwrap_dek(&wrong, &header),
            Err(VaultFormatError::HeaderTampered)
        ));
    }

    #[test]
    fn header_json_is_stable_and_b64_encoded() {
        let header = make_header(&kek(), &dek(), test_kdf()).unwrap();
        let json = serde_json::to_string(&header).unwrap();
        // 字段顺序是格式的一部分
        let v_pos = json.find("\"version\"").unwrap();
        let k_pos = json.find("\"kdf\"").unwrap();
        let n_pos = json.find("\"dek_nonce\"").unwrap();
        let w_pos = json.find("\"wrapped_dek\"").unwrap();
        assert!(v_pos < k_pos && k_pos < n_pos && n_pos < w_pos);
        // 二进制字段不以字节数组形式出现
        assert!(!json.contains('['));
    }

    #[test]
    fn oversized_header_len_is_corrupted() {
        let (header, body) = sample_container();
        let mut bytes = encode(&header, &body).unwrap();
        // 把 header_len 改成超过 payload 的值并重算校验和
        let huge = (bytes.len() as u32).to_le_bytes();
        bytes[8..12].copy_from_slice(&huge);
        let payload_len = bytes.len() - CHECKSUM_LEN;
        let checksum = blake3::hash(&bytes[..payload_len]);
        let csum_start = payload_len;
        bytes[csum_start..].copy_from_slice(checksum.as_bytes());
        assert!(matches!(decode(&bytes), Err(VaultFormatError::Corrupted)));
    }
}
