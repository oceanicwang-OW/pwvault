//! 解锁会话（T1.7）：组合 Vault（信封/文件层）与 Store（内存 DB），
//! 提供 CRUD + 持久化的高层接口。T1.8 的 FFI VaultHandle 将基于本类型。
//!
//! DEK 只在 crate 内从 Vault 流向 Store，绝不经本类型的公开 API 外泄
//! （PDR 3.3 分层禁令）。每次写操作后 flush：序列化内存 DB → 写回库体 →
//! 原子落盘（含滚动备份）。

use std::path::Path;

use crate::kdf::KdfParams;
use crate::secret::SecretString;
use crate::store::{EntryMeta, EntryPlain, Store, StoreError};
use crate::vault::{Vault, VaultError};

#[derive(Debug, thiserror::Error)]
pub enum SessionError {
    #[error(transparent)]
    Vault(#[from] VaultError),
    #[error(transparent)]
    Store(#[from] StoreError),
}

/// 已解锁的库会话。drop 时 Vault/Store 各自的 DEK 随之 zeroize。
pub struct Session {
    vault: Vault,
    store: Store,
}

impl Session {
    /// 建库：初始化空 DB（含 device_id）后立即落盘，确保库体携带
    /// 已初始化的 schema（否则下次解锁会重新生成 device_id）。
    pub fn create(
        path: impl AsRef<Path>,
        password: &SecretString,
        kdf: Option<KdfParams>,
    ) -> Result<Self, SessionError> {
        let vault = Vault::create(path, password, kdf)?;
        let store = Store::open(vault.dek().clone(), vault.body())?;
        let mut session = Self { vault, store };
        session.flush()?;
        Ok(session)
    }

    /// 解锁：打开容器 → 用 DEK 装载内存 DB。
    pub fn unlock(path: impl AsRef<Path>, password: &SecretString) -> Result<Self, SessionError> {
        let vault = Vault::unlock(path, password)?;
        let store = Store::open(vault.dek().clone(), vault.body())?;
        Ok(Self { vault, store })
    }

    /// 改主密码：新盐 + 新 KEK 重包裹同一 DEK（DEK 不变，Store 无需重建）。
    pub fn change_password(
        &mut self,
        old: &SecretString,
        new: &SecretString,
    ) -> Result<(), SessionError> {
        self.vault.change_password(old, new)?;
        Ok(())
    }

    pub fn list_meta(&self) -> Result<Vec<EntryMeta>, SessionError> {
        Ok(self.store.list_meta()?)
    }

    pub fn list_trash(&self) -> Result<Vec<EntryMeta>, SessionError> {
        Ok(self.store.list_trash()?)
    }

    pub fn get_full(&self, id: &str) -> Result<EntryPlain, SessionError> {
        Ok(self.store.get_full(id)?)
    }

    pub fn reveal_password(&self, id: &str) -> Result<SecretString, SessionError> {
        Ok(self.store.reveal_password(id)?)
    }

    pub fn upsert(&mut self, e: EntryPlain) -> Result<EntryMeta, SessionError> {
        let meta = self.store.upsert(e)?;
        self.flush()?;
        Ok(meta)
    }

    pub fn soft_delete(&mut self, id: &str) -> Result<(), SessionError> {
        self.store.soft_delete(id)?;
        self.flush()
    }

    pub fn restore(&mut self, id: &str) -> Result<(), SessionError> {
        self.store.restore(id)?;
        self.flush()
    }

    pub fn path(&self) -> &Path {
        self.vault.path()
    }

    pub fn device_id(&self) -> &str {
        self.store.device_id()
    }

    /// 序列化内存 DB → 写回库体 → 原子落盘（tmp+fsync+rename + 滚动备份）。
    fn flush(&mut self) -> Result<(), SessionError> {
        let body = self.store.serialize()?;
        self.vault.set_body(body);
        self.vault.save()?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pw(s: &str) -> SecretString {
        SecretString::new(s.into())
    }

    fn cheap_kdf() -> KdfParams {
        let mut p = KdfParams::generate().unwrap();
        p.m_kib = 1024;
        p.t_cost = 1;
        p
    }

    fn entry(title: &str) -> EntryPlain {
        EntryPlain {
            id: None,
            title: title.into(),
            username: "user".into(),
            password: pw("pw-secret"),
            url: "https://example.com".into(),
            notes: "note".into(),
            totp_uri: None,
            tags: vec!["t".into()],
            favorite: false,
        }
    }

    #[test]
    fn create_persists_and_unlock_sees_data() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("vault.pwvault");

        let device = {
            let mut s = Session::create(&path, &pw("master"), Some(cheap_kdf())).unwrap();
            s.upsert(entry("淘宝")).unwrap();
            s.device_id().to_string()
        };

        let s2 = Session::unlock(&path, &pw("master")).unwrap();
        let metas = s2.list_meta().unwrap();
        assert_eq!(metas.len(), 1);
        assert_eq!(metas[0].title, "淘宝");
        // device_id 随库持久化，重开不变
        assert_eq!(s2.device_id(), device);
    }

    #[test]
    fn mutations_survive_reopen() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("vault.pwvault");

        let id = {
            let mut s = Session::create(&path, &pw("master"), Some(cheap_kdf())).unwrap();
            let id = s.upsert(entry("a")).unwrap().id;
            s.upsert(entry("b")).unwrap();
            s.soft_delete(&id).unwrap();
            id
        };

        let s2 = Session::unlock(&path, &pw("master")).unwrap();
        assert_eq!(s2.list_meta().unwrap().len(), 1);
        assert_eq!(s2.list_trash().unwrap().len(), 1);
        assert_eq!(s2.list_trash().unwrap()[0].id, id);
        assert_eq!(s2.reveal_password(&id).unwrap().expose(), "pw-secret");
    }

    #[test]
    fn change_password_then_reopen_with_new() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("vault.pwvault");

        {
            let mut s = Session::create(&path, &pw("old"), Some(cheap_kdf())).unwrap();
            s.upsert(entry("keep")).unwrap();
            s.change_password(&pw("old"), &pw("new")).unwrap();
        }

        assert!(Session::unlock(&path, &pw("old")).is_err());
        let s2 = Session::unlock(&path, &pw("new")).unwrap();
        assert_eq!(s2.list_meta().unwrap()[0].title, "keep");
    }
}
