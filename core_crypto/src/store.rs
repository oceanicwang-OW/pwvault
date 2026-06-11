//! 条目存储层（T1.5）：内存 SQLite + 字段级加解密 CRUD。
//!
//! - DB 永远只存在于内存（rusqlite serialize/deserialize 对接容器 Body，
//!   PDR 4.3）；磁盘上只有容器文件。
//! - 全部业务字段密文化：blob = `nonce‖ct‖tag`，AAD = `{entry_id}:{field}`
//!   （cipher::field_aad），防跨字段/跨条目移植。
//! - rev = `device_id:counter`：device_id 建库生成存 meta，counter 单调
//!   递增（推进规则由 T4.1 正式化）。
//! - 软删除写墓碑（deleted_at），密文保留以支持恢复；物理清除归 T4.1。

use rusqlite::{params, Connection, OptionalExtension};

use crate::cipher::{self, CipherError};
use crate::secret::{SecretBytes, SecretString};

/// 条目完整明文（PDR 12.7 契约形状；FFI 暴露在 T1.8）。
#[derive(Debug)]
pub struct EntryPlain {
    /// None = 新建（由 store 分配 UUIDv7）。
    pub id: Option<String>,
    pub title: String,
    pub username: String,
    pub password: SecretString,
    pub url: String,
    pub notes: String,
    pub totp_uri: Option<SecretString>,
    pub tags: Vec<String>,
    pub favorite: bool,
}

/// 条目元数据（永不含密码/备注/TOTP secret）。
#[derive(Debug, Clone, PartialEq)]
pub struct EntryMeta {
    pub id: String,
    pub title: String,
    pub username: String,
    pub url: String,
    pub tags: Vec<String>,
    pub favorite: bool,
    pub has_totp: bool,
    pub created_at: i64,
    pub updated_at: i64,
    pub deleted_at: Option<i64>,
}

#[derive(Debug, thiserror::Error)]
pub enum StoreError {
    #[error("条目不存在: {0}")]
    NotFound(String),
    #[error("数据库错误: {0}")]
    Db(#[from] rusqlite::Error),
    #[error("字段解密失败（密钥错误或数据被篡改）: {0}")]
    Cipher(#[from] CipherError),
    #[error("tags 编码非法")]
    BadTags,
    #[error("数据库镜像非法或版本不支持: {0}")]
    BadImage(String),
}

const SCHEMA_VERSION: i64 = 1;
const MIGRATION_V1: &str = include_str!("../migrations/001_init.sql");

pub struct Store {
    conn: Connection,
    dek: SecretBytes,
    device_id: String,
}

impl Store {
    /// 打开存储：body 为空 → 建新库（写 schema、生成 device_id）；
    /// 否则反序列化镜像并校验 schema 版本。
    pub fn open(dek: SecretBytes, body: &[u8]) -> Result<Self, StoreError> {
        let mut conn = Connection::open_in_memory()?;
        if body.is_empty() {
            conn.execute_batch(MIGRATION_V1)?;
            conn.pragma_update(None, "user_version", SCHEMA_VERSION)?;
        } else {
            conn.deserialize_read_exact(c"main", body, body.len(), false)
                .map_err(|e| StoreError::BadImage(e.to_string()))?;
            let version: i64 = conn.query_row("PRAGMA user_version", [], |r| r.get(0))?;
            if version != SCHEMA_VERSION {
                return Err(StoreError::BadImage(format!(
                    "schema 版本 {version} 不支持"
                )));
            }
        }

        let mut store = Self {
            conn,
            dek,
            device_id: String::new(),
        };
        store.device_id = store.load_or_create_device_id()?;
        Ok(store)
    }

    /// 序列化为容器 Body 镜像。
    pub fn serialize(&self) -> Result<Vec<u8>, StoreError> {
        let data = self.conn.serialize(c"main")?;
        Ok(data.to_vec())
    }

    pub fn device_id(&self) -> &str {
        &self.device_id
    }

    // ---- 条目 CRUD ----

    /// 新建（id=None）或整体更新（id=Some）。返回更新后的元数据。
    pub fn upsert(&mut self, e: EntryPlain) -> Result<EntryMeta, StoreError> {
        let now = now_ms();
        let (id, created_at) = match e.id {
            Some(id) => {
                let created: i64 = self
                    .conn
                    .query_row("SELECT created_at FROM entries WHERE id = ?1", [&id], |r| {
                        r.get(0)
                    })
                    .optional()?
                    .ok_or_else(|| StoreError::NotFound(id.clone()))?;
                (id, created)
            }
            None => (uuid::Uuid::now_v7().to_string(), now),
        };

        let tags_json = serde_json::to_string(&e.tags).map_err(|_| StoreError::BadTags)?;
        let rev = self.next_rev()?;

        let title_ct = self.seal_field(&id, "title", e.title.as_bytes())?;
        let username_ct = self.seal_field(&id, "username", e.username.as_bytes())?;
        let password_ct = self.seal_field(&id, "password", e.password.expose().as_bytes())?;
        let url_ct = self.seal_field(&id, "url", e.url.as_bytes())?;
        let notes_ct = self.seal_field(&id, "notes", e.notes.as_bytes())?;
        let totp_ct = e
            .totp_uri
            .as_ref()
            .map(|t| self.seal_field(&id, "totp", t.expose().as_bytes()))
            .transpose()?;
        let tags_ct = self.seal_field(&id, "tags", tags_json.as_bytes())?;

        self.conn.execute(
            "INSERT INTO entries (id, title_ct, username_ct, password_ct, url_ct, notes_ct,
                                  totp_ct, tags_ct, favorite, created_at, updated_at, deleted_at, rev)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, NULL, ?12)
             ON CONFLICT(id) DO UPDATE SET
               title_ct=excluded.title_ct, username_ct=excluded.username_ct,
               password_ct=excluded.password_ct, url_ct=excluded.url_ct,
               notes_ct=excluded.notes_ct, totp_ct=excluded.totp_ct,
               tags_ct=excluded.tags_ct, favorite=excluded.favorite,
               updated_at=excluded.updated_at, rev=excluded.rev",
            params![
                id,
                title_ct,
                username_ct,
                password_ct,
                url_ct,
                notes_ct,
                totp_ct,
                tags_ct,
                e.favorite as i64,
                created_at,
                now,
                rev,
            ],
        )?;

        self.read_meta_row(&id)
    }

    /// 未删除条目的元数据列表（按 updated_at 降序）。永不解密 password/notes。
    pub fn list_meta(&self) -> Result<Vec<EntryMeta>, StoreError> {
        self.query_meta("deleted_at IS NULL")
    }

    /// 回收站列表（deleted_at 非空）。
    pub fn list_trash(&self) -> Result<Vec<EntryMeta>, StoreError> {
        self.query_meta("deleted_at IS NOT NULL")
    }

    /// 单条目按需解密密码（PDR 6.2：全库密码明文从不同时驻留内存）。
    pub fn reveal_password(&self, id: &str) -> Result<SecretString, StoreError> {
        let ct: Vec<u8> = self
            .conn
            .query_row("SELECT password_ct FROM entries WHERE id = ?1", [id], |r| {
                r.get(0)
            })
            .optional()?
            .ok_or_else(|| StoreError::NotFound(id.into()))?;
        let plain = self.open_field(id, "password", &ct)?;
        Ok(SecretString::new(
            String::from_utf8_lossy(plain.expose()).into_owned(),
        ))
    }

    /// 完整明文（编辑页用）。
    pub fn get_full(&self, id: &str) -> Result<EntryPlain, StoreError> {
        let row = self
            .conn
            .query_row(
                "SELECT title_ct, username_ct, password_ct, url_ct, notes_ct, totp_ct,
                        tags_ct, favorite
                 FROM entries WHERE id = ?1",
                [id],
                |r| {
                    Ok((
                        r.get::<_, Vec<u8>>(0)?,
                        r.get::<_, Vec<u8>>(1)?,
                        r.get::<_, Vec<u8>>(2)?,
                        r.get::<_, Vec<u8>>(3)?,
                        r.get::<_, Vec<u8>>(4)?,
                        r.get::<_, Option<Vec<u8>>>(5)?,
                        r.get::<_, Vec<u8>>(6)?,
                        r.get::<_, i64>(7)?,
                    ))
                },
            )
            .optional()?
            .ok_or_else(|| StoreError::NotFound(id.into()))?;

        let (title_ct, username_ct, password_ct, url_ct, notes_ct, totp_ct, tags_ct, favorite) =
            row;
        let tags_json = self.open_field(id, "tags", &tags_ct)?;
        let tags: Vec<String> =
            serde_json::from_slice(tags_json.expose()).map_err(|_| StoreError::BadTags)?;

        Ok(EntryPlain {
            id: Some(id.to_string()),
            title: self.open_field_string(id, "title", &title_ct)?,
            username: self.open_field_string(id, "username", &username_ct)?,
            password: SecretString::new(self.open_field_string(id, "password", &password_ct)?),
            url: self.open_field_string(id, "url", &url_ct)?,
            notes: self.open_field_string(id, "notes", &notes_ct)?,
            totp_uri: totp_ct
                .map(|ct| {
                    self.open_field_string(id, "totp", &ct)
                        .map(SecretString::new)
                })
                .transpose()?,
            tags,
            favorite: favorite != 0,
        })
    }

    /// 软删除：写墓碑（密文保留以支持恢复）。
    pub fn soft_delete(&mut self, id: &str) -> Result<(), StoreError> {
        let rev = self.next_rev()?;
        let n = self.conn.execute(
            "UPDATE entries SET deleted_at = ?1, updated_at = ?1, rev = ?2 WHERE id = ?3",
            params![now_ms(), rev, id],
        )?;
        if n == 0 {
            return Err(StoreError::NotFound(id.into()));
        }
        Ok(())
    }

    /// 从回收站恢复。
    pub fn restore(&mut self, id: &str) -> Result<(), StoreError> {
        let rev = self.next_rev()?;
        let n = self.conn.execute(
            "UPDATE entries SET deleted_at = NULL, updated_at = ?1, rev = ?2 WHERE id = ?3",
            params![now_ms(), rev, id],
        )?;
        if n == 0 {
            return Err(StoreError::NotFound(id.into()));
        }
        Ok(())
    }

    // ---- meta 表（值加密） ----

    pub fn meta_set(&mut self, key: &str, value: &[u8]) -> Result<(), StoreError> {
        let ct = self.seal_field(&format!("meta:{key}"), "value", value)?;
        self.conn.execute(
            "INSERT INTO meta (key, value_ct) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value_ct = excluded.value_ct",
            params![key, ct],
        )?;
        Ok(())
    }

    pub fn meta_get(&self, key: &str) -> Result<Option<SecretBytes>, StoreError> {
        let ct: Option<Vec<u8>> = self
            .conn
            .query_row("SELECT value_ct FROM meta WHERE key = ?1", [key], |r| {
                r.get(0)
            })
            .optional()?;
        ct.map(|ct| self.open_field(&format!("meta:{key}"), "value", &ct))
            .transpose()
            .map_err(Into::into)
    }

    // ---- 内部 ----

    fn seal_field(&self, id: &str, field: &str, plain: &[u8]) -> Result<Vec<u8>, CipherError> {
        cipher::seal(&self.dek, &cipher::field_aad(id, field), plain)
    }

    fn open_field(&self, id: &str, field: &str, ct: &[u8]) -> Result<SecretBytes, CipherError> {
        cipher::open(&self.dek, &cipher::field_aad(id, field), ct)
    }

    fn open_field_string(&self, id: &str, field: &str, ct: &[u8]) -> Result<String, StoreError> {
        let plain = self.open_field(id, field, ct)?;
        Ok(String::from_utf8_lossy(plain.expose()).into_owned())
    }

    fn query_meta(&self, where_clause: &str) -> Result<Vec<EntryMeta>, StoreError> {
        let sql = format!(
            "SELECT id, title_ct, username_ct, url_ct, tags_ct, totp_ct, favorite,
                    created_at, updated_at, deleted_at
             FROM entries WHERE {where_clause} ORDER BY updated_at DESC"
        );
        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, Vec<u8>>(1)?,
                r.get::<_, Vec<u8>>(2)?,
                r.get::<_, Vec<u8>>(3)?,
                r.get::<_, Vec<u8>>(4)?,
                r.get::<_, Option<Vec<u8>>>(5)?,
                r.get::<_, i64>(6)?,
                r.get::<_, i64>(7)?,
                r.get::<_, i64>(8)?,
                r.get::<_, Option<i64>>(9)?,
            ))
        })?;

        let mut out = Vec::new();
        for row in rows {
            let (id, title_ct, username_ct, url_ct, tags_ct, totp_ct, favorite, c, u, d) = row?;
            let tags_json = self.open_field(&id, "tags", &tags_ct)?;
            let tags: Vec<String> =
                serde_json::from_slice(tags_json.expose()).map_err(|_| StoreError::BadTags)?;
            out.push(EntryMeta {
                title: self.open_field_string(&id, "title", &title_ct)?,
                username: self.open_field_string(&id, "username", &username_ct)?,
                url: self.open_field_string(&id, "url", &url_ct)?,
                tags,
                favorite: favorite != 0,
                has_totp: totp_ct.is_some(),
                created_at: c,
                updated_at: u,
                deleted_at: d,
                id,
            });
        }
        Ok(out)
    }

    fn read_meta_row(&self, id: &str) -> Result<EntryMeta, StoreError> {
        self.query_meta(&format!("id = '{}'", id.replace('\'', "''")))?
            .into_iter()
            .next()
            .ok_or_else(|| StoreError::NotFound(id.into()))
    }

    fn load_or_create_device_id(&mut self) -> Result<String, StoreError> {
        if let Some(v) = self.meta_get("device_id")? {
            return Ok(String::from_utf8_lossy(v.expose()).into_owned());
        }
        let id = uuid::Uuid::now_v7().simple().to_string()[..12].to_string();
        self.meta_set("device_id", id.as_bytes())?;
        Ok(id)
    }

    /// rev 推进：`device_id:counter`，counter 取本设备历史最大值 +1
    /// （正式推进规则与多设备语义归 T4.1）。
    fn next_rev(&mut self) -> Result<String, StoreError> {
        let counter = match self.meta_get("rev_counter")? {
            Some(v) => String::from_utf8_lossy(v.expose())
                .parse::<u64>()
                .unwrap_or(0),
            None => 0,
        } + 1;
        self.meta_set("rev_counter", counter.to_string().as_bytes())?;
        Ok(format!("{}:{}", self.device_id, counter))
    }
}

fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("系统时钟早于 1970")
        .as_millis() as i64
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dek() -> SecretBytes {
        SecretBytes::new(vec![0x42; 32])
    }

    fn sample_entry() -> EntryPlain {
        EntryPlain {
            id: None,
            title: "淘宝".into(),
            username: "owen_dev@163.com".into(),
            password: SecretString::new("kQ9#mTr2!vLp".into()),
            url: "https://taobao.com".into(),
            notes: "secret note marker".into(),
            totp_uri: Some(SecretString::new(
                "otpauth://totp/taobao?secret=JBSWY3DPEHPK3PXP".into(),
            )),
            tags: vec!["个人".into(), "购物".into()],
            favorite: true,
        }
    }

    #[test]
    fn crud_roundtrip() {
        let mut s = Store::open(dek(), &[]).unwrap();
        let meta = s.upsert(sample_entry()).unwrap();
        assert_eq!(meta.title, "淘宝");
        assert_eq!(meta.username, "owen_dev@163.com");
        assert_eq!(meta.url, "https://taobao.com");
        assert_eq!(meta.tags, vec!["个人", "购物"]);
        assert!(meta.favorite);
        assert!(meta.has_totp);
        assert!(meta.deleted_at.is_none());

        let full = s.get_full(&meta.id).unwrap();
        assert_eq!(full.password.expose(), "kQ9#mTr2!vLp");
        assert_eq!(full.notes, "secret note marker");
        assert_eq!(
            full.totp_uri.as_ref().unwrap().expose(),
            "otpauth://totp/taobao?secret=JBSWY3DPEHPK3PXP"
        );

        assert_eq!(
            s.reveal_password(&meta.id).unwrap().expose(),
            "kQ9#mTr2!vLp"
        );
    }

    #[test]
    fn update_preserves_created_at_and_advances_rev() {
        let mut s = Store::open(dek(), &[]).unwrap();
        let meta = s.upsert(sample_entry()).unwrap();
        let rev0 = {
            let m = s.list_meta().unwrap();
            assert_eq!(m.len(), 1);
            // rev 不在 EntryMeta 中暴露，从 DB 直读验证格式
            s.conn
                .query_row("SELECT rev FROM entries WHERE id=?1", [&meta.id], |r| {
                    r.get::<_, String>(0)
                })
                .unwrap()
        };
        assert!(rev0.starts_with(&format!("{}:", s.device_id())));

        let mut e2 = sample_entry();
        e2.id = Some(meta.id.clone());
        e2.title = "淘宝-改".into();
        let meta2 = s.upsert(e2).unwrap();

        assert_eq!(meta2.created_at, meta.created_at);
        assert_eq!(meta2.title, "淘宝-改");
        let rev1: String = s
            .conn
            .query_row("SELECT rev FROM entries WHERE id=?1", [&meta.id], |r| {
                r.get(0)
            })
            .unwrap();
        assert_ne!(rev0, rev1);
        let c0: u64 = rev0.split(':').nth(1).unwrap().parse().unwrap();
        let c1: u64 = rev1.split(':').nth(1).unwrap().parse().unwrap();
        assert!(c1 > c0, "rev counter 必须单调递增");
    }

    /// 验收核心：序列化镜像中不可见任何明文业务字段。
    #[test]
    fn serialized_image_contains_no_plaintext() {
        let mut s = Store::open(dek(), &[]).unwrap();
        s.upsert(sample_entry()).unwrap();
        let image = s.serialize().unwrap();

        let markers: &[&[u8]] = &[
            "淘宝".as_bytes(),
            b"owen_dev@163.com",
            b"kQ9#mTr2!vLp",
            b"taobao.com",
            b"secret note marker",
            b"JBSWY3DPEHPK3PXP",
            "个人".as_bytes(),
            "购物".as_bytes(),
        ];
        for m in markers {
            assert!(
                !contains(&image, m),
                "镜像中发现明文: {:?}",
                String::from_utf8_lossy(m)
            );
        }
    }

    #[test]
    fn image_roundtrip_via_serialize_deserialize() {
        let mut s = Store::open(dek(), &[]).unwrap();
        let meta = s.upsert(sample_entry()).unwrap();
        let image = s.serialize().unwrap();

        let s2 = Store::open(dek(), &image).unwrap();
        let metas = s2.list_meta().unwrap();
        assert_eq!(metas.len(), 1);
        assert_eq!(metas[0], meta);
        assert_eq!(
            s2.reveal_password(&meta.id).unwrap().expose(),
            "kQ9#mTr2!vLp"
        );
        assert_eq!(s2.device_id(), s.device_id(), "device_id 应随库持久化");
    }

    #[test]
    fn soft_delete_writes_tombstone_and_restore_recovers() {
        let mut s = Store::open(dek(), &[]).unwrap();
        let meta = s.upsert(sample_entry()).unwrap();

        s.soft_delete(&meta.id).unwrap();
        assert!(s.list_meta().unwrap().is_empty());
        let trash = s.list_trash().unwrap();
        assert_eq!(trash.len(), 1);
        assert!(trash[0].deleted_at.is_some(), "墓碑必须带 deleted_at");
        assert_eq!(trash[0].id, meta.id);
        // 密文保留，仍可解密（恢复场景）
        assert_eq!(
            s.reveal_password(&meta.id).unwrap().expose(),
            "kQ9#mTr2!vLp"
        );

        s.restore(&meta.id).unwrap();
        assert_eq!(s.list_meta().unwrap().len(), 1);
        assert!(s.list_trash().unwrap().is_empty());
    }

    #[test]
    fn wrong_dek_fails_decryption_not_schema() {
        let mut s = Store::open(dek(), &[]).unwrap();
        s.upsert(sample_entry()).unwrap();
        let image = s.serialize().unwrap();

        let s2 = Store::open(SecretBytes::new(vec![0x43; 32]), &image);
        // schema 可读，但任何解密路径必须失败
        match s2 {
            Ok(s2) => {
                assert!(matches!(s2.list_meta(), Err(StoreError::Cipher(_))));
            }
            Err(_) => {} // device_id 解密失败也可接受
        }
    }

    #[test]
    fn unknown_id_operations_fail() {
        let mut s = Store::open(dek(), &[]).unwrap();
        assert!(matches!(s.get_full("nope"), Err(StoreError::NotFound(_))));
        assert!(matches!(
            s.soft_delete("nope"),
            Err(StoreError::NotFound(_))
        ));
        let mut e = sample_entry();
        e.id = Some("ghost".into());
        assert!(matches!(s.upsert(e), Err(StoreError::NotFound(_))));
    }

    #[test]
    fn entry_ids_are_uuidv7_time_ordered() {
        let mut s = Store::open(dek(), &[]).unwrap();
        let a = s.upsert(sample_entry()).unwrap();
        std::thread::sleep(std::time::Duration::from_millis(2));
        let b = s.upsert(sample_entry()).unwrap();
        assert!(b.id > a.id, "UUIDv7 应时间有序");
    }

    fn contains(haystack: &[u8], needle: &[u8]) -> bool {
        haystack.windows(needle.len()).any(|w| w == needle)
    }
}
