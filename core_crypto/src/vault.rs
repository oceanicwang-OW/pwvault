//! 库生命周期（T1.4，PDR 4.2 信封加密）：create / unlock / lock / change_password。
//!
//! - DEK 建库时随机生成，终身不变；修改主密码只用新 KEK 重包裹 DEK
//!   （新 salt + 新 dek_nonce，毫秒级），全部条目密文不动。
//! - 错误密码与正确密码的耗时由 Argon2id 主导（两条路径执行完全相同的
//!   KDF），解包失败的差异在微秒级，无可利用时序侧信道。
//! - 库头被篡改与密码错误在密码学上不可区分（同为 DEK 解包失败），
//!   解锁路径统一报 [`VaultError::WrongPassword`]。
//!
//! 本模块直接整文件读写；原子写（tmp+fsync+rename）与滚动备份由 T1.6
//! 在 persist.rs 接管。Body 在本阶段为不透明字节串，T1.5 起为 SQLite 镜像。

use std::path::{Path, PathBuf};

use crate::cipher::CipherError;
use crate::kdf::{self, KdfError, KdfParams};
use crate::persist::{self, PersistError};
use crate::secret::{SecretBytes, SecretString};
use crate::vault_format::{self, VaultFormatError, VaultHeader};

/// DEK 长度（AES-256）。
pub const DEK_LEN: usize = 32;

#[derive(Debug, thiserror::Error)]
pub enum VaultError {
    /// ErrWrongPassword（PDR 12.2）：密码错误（或库头被篡改，不可区分）。
    #[error("主密码错误")]
    WrongPassword,
    #[error("库文件已存在: {0}")]
    AlreadyExists(PathBuf),
    #[error("库文件格式错误: {0}")]
    Format(#[from] VaultFormatError),
    #[error("KDF 错误: {0}")]
    Kdf(#[from] KdfError),
    #[error("加密原语错误: {0}")]
    Cipher(#[from] CipherError),
    #[error("IO 错误: {0}")]
    Io(#[from] std::io::Error),
    #[error("持久化错误: {0}")]
    Persist(#[from] PersistError),
    #[error("系统随机源失败")]
    Rng,
}

/// 已解锁的库。drop 时 DEK 自动 zeroize（SecretBytes 语义）。
pub struct Vault {
    path: PathBuf,
    header: VaultHeader,
    dek: SecretBytes,
    body: Vec<u8>,
}

impl Vault {
    /// 建库：新 KDF 参数（默认成本 + 随机盐，可由调用方覆盖）+ 随机 DEK，
    /// 空 Body，落盘后返回已解锁实例。路径已存在则拒绝。
    pub fn create(
        path: impl AsRef<Path>,
        password: &SecretString,
        kdf_params: Option<KdfParams>,
    ) -> Result<Self, VaultError> {
        let path = path.as_ref().to_path_buf();
        if path.exists() {
            return Err(VaultError::AlreadyExists(path));
        }

        let kdf_params = match kdf_params {
            Some(p) => p,
            None => KdfParams::generate()?,
        };
        let mut dek_bytes = vec![0u8; DEK_LEN];
        getrandom::fill(&mut dek_bytes).map_err(|_| VaultError::Rng)?;
        let dek = SecretBytes::new(dek_bytes);

        let kek = kdf::derive_kek(password, &kdf_params)?;
        let header = vault_format::make_header(&kek, &dek, kdf_params)?;

        let vault = Self {
            path,
            header,
            dek,
            body: Vec::new(),
        };
        vault.save()?;
        Ok(vault)
    }

    /// 解锁：读容器 → 派生 KEK → 解包 DEK。
    /// 密码错误（或库头被篡改）报 [`VaultError::WrongPassword`]。
    pub fn unlock(path: impl AsRef<Path>, password: &SecretString) -> Result<Self, VaultError> {
        let path = path.as_ref().to_path_buf();
        let bytes = std::fs::read(&path)?;
        let file = vault_format::decode(&bytes)?;

        let kek = kdf::derive_kek(password, &file.header.kdf)?;
        let dek =
            vault_format::unwrap_dek(&kek, &file.header).map_err(|_| VaultError::WrongPassword)?;

        Ok(Self {
            path,
            header: file.header,
            dek,
            body: file.body,
        })
    }

    /// 锁定：消费自身。DEK 与（未来的）明文缓存随 drop zeroize。
    pub fn lock(self) {
        // drop(self) 即可；显式方法用于表达语义并供 FFI 映射（T1.8）。
    }

    /// 修改主密码：验证旧密码 → 新 KDF 参数（强制新盐）→ 新 KEK 重包裹
    /// 同一 DEK（make_header 内部取新 dek_nonce）→ 落盘。Body 密文不动。
    pub fn change_password(
        &mut self,
        old: &SecretString,
        new: &SecretString,
    ) -> Result<(), VaultError> {
        let old_kek = kdf::derive_kek(old, &self.header.kdf)?;
        vault_format::unwrap_dek(&old_kek, &self.header).map_err(|_| VaultError::WrongPassword)?;

        let new_params = KdfParams::generate()?;
        debug_assert_ne!(new_params.salt, self.header.kdf.salt);
        let new_kek = kdf::derive_kek(new, &new_params)?;
        self.header = vault_format::make_header(&new_kek, &self.dek, new_params)?;
        self.save()
    }

    /// 序列化容器并原子写盘（tmp + fsync + rename）+ 滚动备份（T1.6）。
    pub fn save(&self) -> Result<(), VaultError> {
        let bytes = vault_format::encode(&self.header, &self.body)?;
        persist::save_atomic(&self.path, &bytes)?;
        Ok(())
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn header(&self) -> &VaultHeader {
        &self.header
    }

    /// DEK 访问（仅 crate 内：store/merge 层用，永不跨 FFI）。
    pub(crate) fn dek(&self) -> &SecretBytes {
        &self.dek
    }

    /// Body 读写（T1.5 store 层接管；当前为不透明字节）。
    pub fn body(&self) -> &[u8] {
        &self.body
    }

    pub fn set_body(&mut self, body: Vec<u8>) {
        self.body = body;
    }
}

#[cfg(test)]
mod tests {
    use std::time::{Duration, Instant};

    use super::*;
    use crate::kdf::SALT_LEN;

    fn pw(s: &str) -> SecretString {
        SecretString::new(s.into())
    }

    /// 低成本 KDF（仅测试加速；盐仍随机）。
    fn cheap_kdf() -> KdfParams {
        let mut p = KdfParams::generate().unwrap();
        p.m_kib = 1024;
        p.t_cost = 1;
        p
    }

    fn temp_vault_path(dir: &tempfile::TempDir) -> PathBuf {
        dir.path().join("vault.pwvault")
    }

    #[test]
    fn create_unlock_roundtrip_preserves_dek_and_body() {
        let dir = tempfile::tempdir().unwrap();
        let path = temp_vault_path(&dir);

        let mut v = Vault::create(&path, &pw("master"), Some(cheap_kdf())).unwrap();
        let dek0 = v.dek().expose().to_vec();
        v.set_body(b"pretend sqlite image".to_vec());
        v.save().unwrap();
        v.lock();

        let v2 = Vault::unlock(&path, &pw("master")).unwrap();
        assert_eq!(v2.dek().expose(), &dek0[..]);
        assert_eq!(v2.body(), b"pretend sqlite image");
    }

    #[test]
    fn wrong_password_is_rejected() {
        let dir = tempfile::tempdir().unwrap();
        let path = temp_vault_path(&dir);
        Vault::create(&path, &pw("master"), Some(cheap_kdf())).unwrap();

        assert!(matches!(
            Vault::unlock(&path, &pw("not-master")),
            Err(VaultError::WrongPassword)
        ));
    }

    /// 验收：错误密码耗时与正确路径相近（两者都跑满同一 Argon2id）。
    /// 用中等成本参数放大 KDF 占比；阈值放宽到 30% 以避免 CI 抖动误报，
    /// 仍足以捕获“未跑 KDF 就提前返回”这类侧信道缺陷（那会 <1%）。
    #[test]
    fn wrong_password_timing_is_close_to_correct() {
        let dir = tempfile::tempdir().unwrap();
        let path = temp_vault_path(&dir);
        let mut params = KdfParams::generate().unwrap();
        params.m_kib = 8 * 1024;
        params.t_cost = 2;
        Vault::create(&path, &pw("master"), Some(params)).unwrap();

        let t = Instant::now();
        Vault::unlock(&path, &pw("master")).unwrap();
        let correct = t.elapsed();

        let t = Instant::now();
        let _ = Vault::unlock(&path, &pw("wrong"));
        let wrong = t.elapsed();

        assert!(correct > Duration::from_millis(5), "成本参数过低，测试失真");
        assert!(
            wrong.as_secs_f64() >= correct.as_secs_f64() * 0.3,
            "错误密码路径耗时 {wrong:?} 远低于正确路径 {correct:?}，存在提前返回侧信道"
        );
    }

    /// 验收核心：改密后旧密码失效、新密码可解锁、DEK 不变、Body 密文
    /// 逐字节不变（无需重加密条目）、salt 与 dek_nonce 强制更新。
    #[test]
    fn change_password_rewraps_dek_only() {
        let dir = tempfile::tempdir().unwrap();
        let path = temp_vault_path(&dir);

        let mut v = Vault::create(&path, &pw("old-pass"), Some(cheap_kdf())).unwrap();
        v.set_body(b"encrypted entries stand-in".to_vec());
        v.save().unwrap();

        let dek0 = v.dek().expose().to_vec();
        let old_salt = v.header().kdf.salt.clone();
        let old_nonce = v.header().dek_nonce.clone();
        let old_wrapped = v.header().wrapped_dek.clone();
        let body0 = v.body().to_vec();

        v.change_password(&pw("old-pass"), &pw("new-pass")).unwrap();

        // Header 三要素全部更新
        assert_ne!(v.header().kdf.salt, old_salt, "改密必须重新生成 salt");
        assert_eq!(v.header().kdf.salt.len(), SALT_LEN);
        assert_ne!(v.header().dek_nonce, old_nonce, "改密必须更换 dek_nonce");
        assert_ne!(v.header().wrapped_dek, old_wrapped);
        // DEK 与 Body 密文不变
        assert_eq!(v.dek().expose(), &dek0[..]);
        assert_eq!(v.body(), &body0[..]);

        // 旧密码失效、新密码可用，且落盘内容一致
        assert!(matches!(
            Vault::unlock(&path, &pw("old-pass")),
            Err(VaultError::WrongPassword)
        ));
        let v2 = Vault::unlock(&path, &pw("new-pass")).unwrap();
        assert_eq!(v2.dek().expose(), &dek0[..]);
        assert_eq!(v2.body(), &body0[..]);
    }

    #[test]
    fn change_password_with_wrong_old_keeps_state() {
        let dir = tempfile::tempdir().unwrap();
        let path = temp_vault_path(&dir);
        let mut v = Vault::create(&path, &pw("master"), Some(cheap_kdf())).unwrap();
        let header0 = v.header().clone();

        assert!(matches!(
            v.change_password(&pw("oops"), &pw("new")),
            Err(VaultError::WrongPassword)
        ));
        assert_eq!(v.header(), &header0, "失败的改密不得改动 Header");
        assert!(Vault::unlock(&path, &pw("master")).is_ok());
    }

    /// 端到端验收：保存中途崩溃（rename 前）后整库仍能用旧密码解锁、
    /// 内容完整（原子写 + 库尾 checksum 共同保证）。
    #[test]
    fn crash_during_save_leaves_vault_openable() {
        use crate::persist::{save_atomic_impl, FaultPoint};

        let dir = tempfile::tempdir().unwrap();
        let path = temp_vault_path(&dir);

        let mut v = Vault::create(&path, &pw("master"), Some(cheap_kdf())).unwrap();
        v.set_body(b"committed-body-v1".to_vec());
        v.save().unwrap();

        // 模拟写新版时在 rename 前崩溃
        let new_bytes = crate::vault_format::encode(v.header(), b"half-written-v2").unwrap();
        let err = save_atomic_impl(&path, &new_bytes, FaultPoint::AfterTmpBeforeRename);
        assert!(err.is_err());

        // 重新解锁：主文件仍是 v1，checksum 通过，内容完整
        let v2 = Vault::unlock(&path, &pw("master")).unwrap();
        assert_eq!(v2.body(), b"committed-body-v1");
    }

    /// 备份是有效容器：可用同一主密码独立解锁出旧版内容。
    #[test]
    fn rolled_backup_is_a_decryptable_vault() {
        let dir = tempfile::tempdir().unwrap();
        let path = temp_vault_path(&dir);

        // create 自身 save 一次（空 body 入备份），故 v1 是第 2 个备份
        let mut v = Vault::create(&path, &pw("master"), Some(cheap_kdf())).unwrap();
        v.set_body(b"body-v1".to_vec());
        v.save().unwrap();
        v.set_body(b"body-v2".to_vec());
        v.save().unwrap(); // 触发 v1 滚入备份

        let backups =
            crate::persist::list_backups_for_test(&dir.path().join("backups"), "vault.pwvault");
        assert_eq!(backups.len(), 2, "空 body 与 v1 各一份备份");
        // 最新备份（v1）可独立解锁出旧版内容
        let v_old = Vault::unlock(backups.last().unwrap(), &pw("master")).unwrap();
        assert_eq!(v_old.body(), b"body-v1");
    }

    #[test]
    fn create_refuses_existing_path() {
        let dir = tempfile::tempdir().unwrap();
        let path = temp_vault_path(&dir);
        Vault::create(&path, &pw("a"), Some(cheap_kdf())).unwrap();
        assert!(matches!(
            Vault::create(&path, &pw("a"), Some(cheap_kdf())),
            Err(VaultError::AlreadyExists(_))
        ));
    }

    #[test]
    fn unlock_missing_or_corrupted_file() {
        let dir = tempfile::tempdir().unwrap();
        assert!(matches!(
            Vault::unlock(dir.path().join("nope.pwvault"), &pw("a")),
            Err(VaultError::Io(_))
        ));

        let path = temp_vault_path(&dir);
        Vault::create(&path, &pw("a"), Some(cheap_kdf())).unwrap();
        let mut bytes = std::fs::read(&path).unwrap();
        let last = bytes.len() - 1;
        bytes[last] ^= 0x01; // 破坏 Trailer
        std::fs::write(&path, bytes).unwrap();
        assert!(matches!(
            Vault::unlock(&path, &pw("a")),
            Err(VaultError::Format(VaultFormatError::Corrupted))
        ));
    }
}
