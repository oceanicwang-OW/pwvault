//! Argon2id 密钥派生（T1.1）。
//!
//! PDR 4.2：`KEK = Argon2id(password, salt, m=64MB, t=3, p=4)`，输出 32 字节
//! （AES-256 密钥）。参数结构随库头 Header 序列化（PDR 4.3），salt 编码为 base64。

use argon2::{Algorithm, Argon2, Params, Version};
use serde::{Deserialize, Serialize};

use crate::secret::{SecretBytes, SecretString};

/// KEK 输出长度（AES-256）。
pub const KEK_LEN: usize = 32;
/// 盐长度（RFC 9106 推荐 128-bit）。
pub const SALT_LEN: usize = 16;

/// 默认成本参数（PDR 4.2）。
pub const DEFAULT_M_KIB: u32 = 64 * 1024; // 64 MB
pub const DEFAULT_T_COST: u32 = 3;
pub const DEFAULT_P_LANES: u32 = 4;

/// KDF 参数（PDR 12.7 契约类型；库头 `kdf` 字段）。
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct KdfParams {
    /// 目前仅支持 "argon2id"；其他值解锁时报 [`KdfError::UnsupportedAlgo`]。
    pub algo: String,
    #[serde(with = "b64")]
    pub salt: Vec<u8>,
    pub m_kib: u32,
    pub t_cost: u32,
    pub p_lanes: u32,
}

impl KdfParams {
    /// 默认成本 + 新随机盐。建库与修改主密码时调用——
    /// 改密必须换盐（T1.4 验收），防止旧盐上的预计算成果迁移。
    pub fn generate() -> Result<Self, KdfError> {
        let mut salt = vec![0u8; SALT_LEN];
        getrandom::fill(&mut salt).map_err(|_| KdfError::Rng)?;
        Ok(Self {
            algo: "argon2id".into(),
            salt,
            m_kib: DEFAULT_M_KIB,
            t_cost: DEFAULT_T_COST,
            p_lanes: DEFAULT_P_LANES,
        })
    }
}

#[derive(Debug, thiserror::Error)]
pub enum KdfError {
    #[error("不支持的 KDF 算法: {0}")]
    UnsupportedAlgo(String),
    #[error("非法 KDF 参数")]
    InvalidParams,
    #[error("系统随机源失败")]
    Rng,
}

/// 由主密码派生 KEK。耗时与成本参数成正比（默认参数约数百毫秒，按设计）。
pub fn derive_kek(password: &SecretString, params: &KdfParams) -> Result<SecretBytes, KdfError> {
    if params.algo != "argon2id" {
        return Err(KdfError::UnsupportedAlgo(params.algo.clone()));
    }
    let a2_params = Params::new(params.m_kib, params.t_cost, params.p_lanes, Some(KEK_LEN))
        .map_err(|_| KdfError::InvalidParams)?;
    let a2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, a2_params);
    let mut out = vec![0u8; KEK_LEN];
    a2.hash_password_into(password.expose().as_bytes(), &params.salt, &mut out)
        .map_err(|_| KdfError::InvalidParams)?;
    Ok(SecretBytes::new(out))
}

/// salt 的 base64 serde 编解码（对齐 PDR 4.3 Header JSON）。
mod b64 {
    use base64::engine::general_purpose::STANDARD;
    use base64::Engine as _;
    use serde::{Deserialize, Deserializer, Serializer};

    pub fn serialize<S: Serializer>(v: &[u8], s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&STANDARD.encode(v))
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<Vec<u8>, D::Error> {
        let s = String::deserialize(d)?;
        STANDARD.decode(s).map_err(serde::de::Error::custom)
    }
}

#[cfg(test)]
mod tests {
    use argon2::{AssociatedData, ParamsBuilder};

    use super::*;

    /// RFC 9106 §5.3 Argon2id 已知向量（含 secret 与 associated data，
    /// 经底层 API 复现；生产路径 derive_kek 不使用 secret/ad）。
    #[test]
    fn rfc9106_argon2id_known_answer() {
        let password = [0x01u8; 32];
        let salt = [0x02u8; 16];
        let secret = [0x03u8; 8];
        let ad = [0x04u8; 12];

        let params = ParamsBuilder::new()
            .m_cost(32)
            .t_cost(3)
            .p_cost(4)
            .data(AssociatedData::new(&ad).unwrap())
            .output_len(32)
            .build()
            .unwrap();
        let a2 =
            Argon2::new_with_secret(&secret, Algorithm::Argon2id, Version::V0x13, params).unwrap();
        let mut out = [0u8; 32];
        a2.hash_password_into(&password, &salt, &mut out).unwrap();

        assert_eq!(
            hex::encode(out),
            "0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659"
        );
    }

    fn cheap_params(salt: Vec<u8>) -> KdfParams {
        KdfParams {
            algo: "argon2id".into(),
            salt,
            m_kib: 1024,
            t_cost: 1,
            p_lanes: 4,
        }
    }

    #[test]
    fn derive_kek_is_deterministic_and_input_sensitive() {
        let pw = SecretString::new("correct horse battery staple".into());
        let params = cheap_params(vec![0x11; SALT_LEN]);

        let k1 = derive_kek(&pw, &params).unwrap();
        let k2 = derive_kek(&pw, &params).unwrap();
        assert_eq!(k1.expose(), k2.expose());
        assert_eq!(k1.len(), KEK_LEN);

        let k3 = derive_kek(&SecretString::new("wrong password".into()), &params).unwrap();
        assert_ne!(k1.expose(), k3.expose());

        let k4 = derive_kek(&pw, &cheap_params(vec![0x22; SALT_LEN])).unwrap();
        assert_ne!(k1.expose(), k4.expose());
    }

    #[test]
    fn derive_kek_with_default_production_params() {
        let pw = SecretString::new("master".into());
        let params = KdfParams::generate().unwrap();
        assert_eq!(params.m_kib, DEFAULT_M_KIB);
        assert_eq!(params.t_cost, DEFAULT_T_COST);
        assert_eq!(params.p_lanes, DEFAULT_P_LANES);
        assert_eq!(derive_kek(&pw, &params).unwrap().len(), KEK_LEN);
    }

    #[test]
    fn generate_uses_fresh_salts() {
        let a = KdfParams::generate().unwrap();
        let b = KdfParams::generate().unwrap();
        assert_eq!(a.salt.len(), SALT_LEN);
        assert_ne!(a.salt, b.salt, "两次生成的盐不应相同");
    }

    #[test]
    fn params_serde_roundtrip_with_base64_salt() {
        let p = cheap_params(vec![0xAB; SALT_LEN]);
        let json = serde_json::to_string(&p).unwrap();
        assert!(
            json.contains("\"q6urq6urq6urq6urq6urqw==\""),
            "salt 应序列化为 base64 字符串: {json}"
        );
        let back: KdfParams = serde_json::from_str(&json).unwrap();
        assert_eq!(p, back);
    }

    #[test]
    fn unsupported_algo_is_rejected() {
        let mut p = cheap_params(vec![0u8; SALT_LEN]);
        p.algo = "md5".into();
        let pw = SecretString::new("x".into());
        assert!(matches!(
            derive_kek(&pw, &p),
            Err(KdfError::UnsupportedAlgo(_))
        ));
    }
}
