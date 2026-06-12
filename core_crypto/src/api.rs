//! FFI API 暴露层（T1.8）：按 PDR 12.7 契约暴露库生命周期与条目 CRUD。
//!
//! - `VaultHandle` 为不透明句柄（内含 [`Session`]）；Dart 只持有句柄，
//!   永不接触 KEK/DEK 字节。句柄被 Dart 释放（dispose/GC）即锁定，
//!   Rust 侧 Session drop 时 zeroize 密钥。
//! - 主密码以 `String` 跨界（UI 输入的必经之路），进入 Rust 立即包进
//!   SecretString。entry_reveal_password / get_full 返回明文 String 供
//!   "点击显示" / 编辑页用，调用方（Dart）负责及时丢弃。
//! - 错误统一为 `"CODE: message"` 字符串，Dart 侧（T2.1 VaultService）
//!   按 CODE 前缀映射领域异常。CODE ∈ {WRONG_PASSWORD, ALREADY_EXISTS,
//!   NOT_FOUND, CORRUPTED, UNSUPPORTED_VERSION, ERROR}。
//!
//! 普通（非 async）Rust 函数经 flutter_rust_bridge 自动在 worker 线程执行、
//! 在 Dart 侧呈现为 Future，不阻塞 UI（KDF/解密为计算密集型）。
//! 工具类（generate_password/totp_now）与 vault_merge 在各自任务（T2.5/
//! T5.3/T4.2）接入，此处先定稿库与条目 CRUD 面。

use std::sync::Mutex;

use flutter_rust_bridge::frb;

use crate::secret::SecretString;
use crate::session::{Session, SessionError};
use crate::store::{EntryMeta, EntryPlain, StoreError};
use crate::vault::VaultError;

/// 连通性探针：返回 crate 名与版本，供三端验证 FFI 链路。
#[frb(sync)]
pub fn ping() -> String {
    format!("core_crypto {}", env!("CARGO_PKG_VERSION"))
}

/// 条目明文（FFI 输入/输出，全部字段为普通 String）。
/// 输入（upsert）：id=None 为新建。输出（get_full）：id=Some。
#[derive(Debug, Clone)]
pub struct EntryDraft {
    pub id: Option<String>,
    pub title: String,
    pub username: String,
    pub password: String,
    pub url: String,
    pub notes: String,
    pub totp_uri: Option<String>,
    pub tags: Vec<String>,
    pub favorite: bool,
}

impl From<EntryDraft> for EntryPlain {
    fn from(d: EntryDraft) -> Self {
        EntryPlain {
            id: d.id,
            title: d.title,
            username: d.username,
            password: SecretString::new(d.password),
            url: d.url,
            notes: d.notes,
            totp_uri: d.totp_uri.map(SecretString::new),
            tags: d.tags,
            favorite: d.favorite,
        }
    }
}

impl EntryDraft {
    fn from_plain(p: EntryPlain) -> Self {
        EntryDraft {
            id: p.id,
            title: p.title,
            username: p.username,
            password: p.password.expose().to_string(),
            url: p.url,
            notes: p.notes,
            totp_uri: p.totp_uri.map(|t| t.expose().to_string()),
            tags: p.tags,
            favorite: p.favorite,
        }
    }
}

/// 不透明库句柄（PDR 12.7 VaultHandle）。
///
/// 内部用 `Mutex<Session>`：rusqlite `Connection` 是 `!Sync`，而 frb 句柄
/// 需 `Send + Sync`；`Mutex<T>: Sync` 仅要求 `T: Send`（Session 满足），
/// 故全部方法取 `&self` 在内部加锁，对外仍是单一可变会话语义。
#[frb(opaque)]
pub struct VaultHandle {
    inner: Mutex<Session>,
}

impl VaultHandle {
    fn wrap(session: Session) -> VaultHandle {
        VaultHandle {
            inner: Mutex::new(session),
        }
    }

    /// 建库并解锁。路径已存在则报 ALREADY_EXISTS。
    pub fn create(path: String, password: String) -> Result<VaultHandle, String> {
        let pw = SecretString::new(password);
        Session::create(path, &pw, None)
            .map(VaultHandle::wrap)
            .map_err(emap)
    }

    /// 解锁现有库。密码错误（或库头篡改）报 WRONG_PASSWORD。
    pub fn unlock(path: String, password: String) -> Result<VaultHandle, String> {
        let pw = SecretString::new(password);
        Session::unlock(path, &pw)
            .map(VaultHandle::wrap)
            .map_err(emap)
    }

    /// 改主密码（新盐 + 新 KEK 重包裹同一 DEK）。
    pub fn change_password(&self, old: String, new: String) -> Result<(), String> {
        self.lock()
            .change_password(&SecretString::new(old), &SecretString::new(new))
            .map_err(emap)
    }

    /// 未删除条目元数据（永不含密码/备注/TOTP secret）。
    pub fn list_meta(&self) -> Result<Vec<EntryMeta>, String> {
        self.lock().list_meta().map_err(emap)
    }

    /// 回收站条目元数据。
    pub fn list_trash(&self) -> Result<Vec<EntryMeta>, String> {
        self.lock().list_trash().map_err(emap)
    }

    /// 单条按需解密密码（"点击显示"；调用方负责 10s 内丢弃返回串）。
    pub fn reveal_password(&self, id: String) -> Result<String, String> {
        self.lock()
            .reveal_password(&id)
            .map(|s| s.expose().to_string())
            .map_err(emap)
    }

    /// 完整明文（编辑页用）。
    pub fn get_full(&self, id: String) -> Result<EntryDraft, String> {
        self.lock()
            .get_full(&id)
            .map(EntryDraft::from_plain)
            .map_err(emap)
    }

    /// 新建或整体更新条目，返回更新后的元数据。
    pub fn upsert(&self, draft: EntryDraft) -> Result<EntryMeta, String> {
        self.lock().upsert(draft.into()).map_err(emap)
    }

    /// 软删除（写墓碑）。
    pub fn soft_delete(&self, id: String) -> Result<(), String> {
        self.lock().soft_delete(&id).map_err(emap)
    }

    /// 从回收站恢复。
    pub fn restore(&self, id: String) -> Result<(), String> {
        self.lock().restore(&id).map_err(emap)
    }

    /// 本设备 id（rev 前缀）。
    pub fn device_id(&self) -> String {
        self.lock().device_id().to_string()
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, Session> {
        self.inner.lock().unwrap_or_else(|e| e.into_inner())
    }
}

/// 领域错误 → `"CODE: message"`。
fn emap(e: SessionError) -> String {
    let code = match &e {
        SessionError::Vault(VaultError::WrongPassword) => "WRONG_PASSWORD",
        SessionError::Vault(VaultError::AlreadyExists(_)) => "ALREADY_EXISTS",
        SessionError::Store(StoreError::NotFound(_)) => "NOT_FOUND",
        _ => "ERROR",
    };
    format!("{code}: {e}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ping_returns_crate_version() {
        assert_eq!(ping(), format!("core_crypto {}", env!("CARGO_PKG_VERSION")));
    }

    fn fast_create(path: &std::path::Path) -> VaultHandle {
        // 经 Session 直接建库（生产 KDF），再以句柄包装——
        // 这里走 create 全路径，验证 emap 与转换无误
        VaultHandle::create(path.to_string_lossy().into_owned(), "master".into()).unwrap()
    }

    #[test]
    fn handle_crud_lifecycle() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("vault.pwvault");
        let h = fast_create(&path);

        let draft = EntryDraft {
            id: None,
            title: "淘宝".into(),
            username: "owen".into(),
            password: "kQ9#mTr2".into(),
            url: "taobao.com".into(),
            notes: "n".into(),
            totp_uri: Some("otpauth://x".into()),
            tags: vec!["个人".into()],
            favorite: true,
        };
        let meta = h.upsert(draft).unwrap();
        assert_eq!(meta.title, "淘宝");
        assert!(meta.has_totp);

        assert_eq!(h.list_meta().unwrap().len(), 1);
        assert_eq!(h.reveal_password(meta.id.clone()).unwrap(), "kQ9#mTr2");

        let full = h.get_full(meta.id.clone()).unwrap();
        assert_eq!(full.password, "kQ9#mTr2");
        assert_eq!(full.totp_uri.as_deref(), Some("otpauth://x"));

        h.soft_delete(meta.id.clone()).unwrap();
        assert!(h.list_meta().unwrap().is_empty());
        assert_eq!(h.list_trash().unwrap().len(), 1);
        h.restore(meta.id.clone()).unwrap();
        assert_eq!(h.list_meta().unwrap().len(), 1);
    }

    #[test]
    fn error_codes_are_prefixed() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("vault.pwvault");
        VaultHandle::create(path.to_string_lossy().into_owned(), "master".into()).unwrap();

        let dup = VaultHandle::create(path.to_string_lossy().into_owned(), "x".into())
            .err()
            .expect("重复建库应失败");
        assert!(dup.starts_with("ALREADY_EXISTS:"));

        let wrong = VaultHandle::unlock(path.to_string_lossy().into_owned(), "nope".into())
            .err()
            .expect("错误密码应失败");
        assert!(wrong.starts_with("WRONG_PASSWORD:"));

        let h = VaultHandle::unlock(path.to_string_lossy().into_owned(), "master".into()).unwrap();
        assert!(h
            .get_full("ghost".into())
            .unwrap_err()
            .starts_with("NOT_FOUND:"));
    }
}
