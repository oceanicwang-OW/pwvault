//! 原子写与滚动备份（T1.6，PDR 2.2「写临时文件 + rename」/ 6.4 / 10）。
//!
//! 写流程：先把现有库文件滚动进 `backups/`（保留最近 [`MAX_BACKUPS`] 版），
//! 再写 `<name>.tmp` → fsync → 原子 rename。崩溃/断电只可能留下一个无害的
//! 半写 tmp，主文件要么是旧版完整内容、要么是新版完整内容，绝不半写。
//!
//! 库尾 BLAKE3 校验和由 [`crate::vault_format::decode`] 在打开时验证：
//! 任何半写/损坏的文件都会被 checksum 拒绝，与本层的原子性互补。
//!
//! 备份文件是加密容器的逐字节副本，仍受零知识保护，可安全留存。

use std::fs::File;
use std::io::Write;
use std::path::{Path, PathBuf};

/// 备份子目录名（位于库文件同目录下）。
pub const BACKUP_DIR: &str = "backups";
/// 滚动保留的备份版本数。
pub const MAX_BACKUPS: usize = 20;

#[derive(Debug, thiserror::Error)]
pub enum PersistError {
    #[error("IO 错误: {0}")]
    Io(#[from] std::io::Error),
}

/// 故障注入点（仅供测试模拟崩溃；生产路径始终传 [`FaultPoint::None`]）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum FaultPoint {
    None,
    /// tmp 已写入并 fsync、rename 之前崩溃。
    AfterTmpBeforeRename,
}

/// 原子写库文件：滚动备份现有版本 → tmp + fsync + 原子 rename。
pub fn save_atomic(path: &Path, bytes: &[u8]) -> Result<(), PersistError> {
    save_atomic_impl(path, bytes, FaultPoint::None)
}

pub(crate) fn save_atomic_impl(
    path: &Path,
    bytes: &[u8],
    fault: FaultPoint,
) -> Result<(), PersistError> {
    rotate_backup(path)?;

    let tmp = sibling(path, ".tmp");
    {
        let mut f = File::create(&tmp)?;
        f.write_all(bytes)?;
        f.sync_all()?; // fsync：数据落盘后才允许 rename
    }

    if fault == FaultPoint::AfterTmpBeforeRename {
        // 模拟崩溃：tmp 已落盘但未提交，主文件保持旧版
        return Err(PersistError::Io(std::io::Error::other(
            "injected crash before rename",
        )));
    }

    std::fs::rename(&tmp, path)?;
    sync_parent_dir(path)?;
    Ok(())
}

/// 把现有库文件复制进 `backups/`，并把版本数修剪到 [`MAX_BACKUPS`]。
/// 主文件不存在（首次建库）时为 no-op。
fn rotate_backup(path: &Path) -> Result<(), PersistError> {
    if !path.exists() {
        return Ok(());
    }
    let dir = parent_dir(path);
    let backup_dir = dir.join(BACKUP_DIR);
    std::fs::create_dir_all(&backup_dir)?;

    let file_name = path
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();

    let mut existing = list_backups(&backup_dir, &file_name)?;
    let next_seq = existing.iter().map(|(s, _)| *s).max().map_or(0, |m| m + 1);
    let backup_path = backup_dir.join(format!("{file_name}.{next_seq:010}.bak"));
    std::fs::copy(path, &backup_path)?;
    existing.push((next_seq, backup_path));

    // 保留最新 MAX_BACKUPS 个（seq 越大越新），淘汰最旧
    existing.sort_by_key(|(s, _)| *s);
    while existing.len() > MAX_BACKUPS {
        let (_, oldest) = existing.remove(0);
        std::fs::remove_file(oldest)?;
    }
    Ok(())
}

/// 列出 `backups/` 中属于该库的备份：文件名形如 `<name>.<seq>.bak`。
fn list_backups(backup_dir: &Path, file_name: &str) -> Result<Vec<(u64, PathBuf)>, PersistError> {
    let prefix = format!("{file_name}.");
    let mut out = Vec::new();
    for entry in std::fs::read_dir(backup_dir)? {
        let entry = entry?;
        let name = entry.file_name().to_string_lossy().into_owned();
        if let Some(seq) = name
            .strip_prefix(&prefix)
            .and_then(|rest| rest.strip_suffix(".bak"))
            .and_then(|s| s.parse::<u64>().ok())
        {
            out.push((seq, entry.path()));
        }
    }
    Ok(out)
}

fn parent_dir(path: &Path) -> PathBuf {
    path.parent()
        .filter(|p| !p.as_os_str().is_empty())
        .map(Path::to_path_buf)
        .unwrap_or_else(|| PathBuf::from("."))
}

/// 在 path 同目录下构造带后缀的兄弟路径（保留完整文件名，仅追加后缀）。
fn sibling(path: &Path, suffix: &str) -> PathBuf {
    let mut name = path
        .file_name()
        .map(|n| n.to_os_string())
        .unwrap_or_default();
    name.push(suffix);
    path.with_file_name(name)
}

#[cfg(unix)]
fn sync_parent_dir(path: &Path) -> Result<(), PersistError> {
    // rename 的目录项变更也需落盘
    let dir = parent_dir(path);
    File::open(dir)?.sync_all()?;
    Ok(())
}

#[cfg(not(unix))]
fn sync_parent_dir(_path: &Path) -> Result<(), PersistError> {
    // Windows 的 rename（MoveFileEx + REPLACE_EXISTING）自带目录项持久化语义
    Ok(())
}

/// 测试辅助：列出某库的备份路径，按 seq 升序（旧→新）。
#[cfg(test)]
pub fn list_backups_for_test(backup_dir: &Path, file_name: &str) -> Vec<PathBuf> {
    let mut b = list_backups(backup_dir, file_name).unwrap();
    b.sort_by_key(|(s, _)| *s);
    b.into_iter().map(|(_, p)| p).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir() -> tempfile::TempDir {
        tempfile::tempdir().unwrap()
    }

    #[test]
    fn atomic_write_roundtrip() {
        let dir = temp_dir();
        let path = dir.path().join("vault.pwvault");
        save_atomic(&path, b"hello").unwrap();
        assert_eq!(std::fs::read(&path).unwrap(), b"hello");

        save_atomic(&path, b"world!!").unwrap();
        assert_eq!(std::fs::read(&path).unwrap(), b"world!!");
    }

    #[test]
    fn first_write_creates_no_backup() {
        let dir = temp_dir();
        let path = dir.path().join("vault.pwvault");
        save_atomic(&path, b"v1").unwrap();
        assert!(!dir.path().join(BACKUP_DIR).exists());
    }

    /// 验收：tmp 写完、rename 前崩溃 → 主文件保持旧版完整内容。
    #[test]
    fn crash_before_rename_keeps_old_content() {
        let dir = temp_dir();
        let path = dir.path().join("vault.pwvault");
        save_atomic(&path, b"good-v1").unwrap();

        let err = save_atomic_impl(&path, b"new-v2-XXXX", FaultPoint::AfterTmpBeforeRename);
        assert!(err.is_err());

        // 主文件未被破坏，仍是 v1
        assert_eq!(std::fs::read(&path).unwrap(), b"good-v1");
    }

    #[test]
    fn overwrite_backs_up_previous_version() {
        let dir = temp_dir();
        let path = dir.path().join("vault.pwvault");
        save_atomic(&path, b"v1").unwrap();
        save_atomic(&path, b"v2").unwrap();

        let backups = list_backups(&dir.path().join(BACKUP_DIR), "vault.pwvault").unwrap();
        assert_eq!(backups.len(), 1, "覆盖应产生 1 个备份");
        assert_eq!(std::fs::read(&backups[0].1).unwrap(), b"v1");
    }

    /// 验收：第 21 次备份淘汰最旧（保持恰好 MAX_BACKUPS 个）。
    #[test]
    fn rotation_evicts_oldest_beyond_max() {
        let dir = temp_dir();
        let path = dir.path().join("vault.pwvault");
        // 写 MAX_BACKUPS + 3 次：首次无备份，其后每次备份上一版，
        // 共产生 seq 0..=MAX_BACKUPS+1 个备份，应淘汰最旧的 seq 0、1。
        let writes = MAX_BACKUPS + 3;
        for i in 0..writes {
            save_atomic(&path, format!("version-{i}").as_bytes()).unwrap();
        }

        let mut backups = list_backups(&dir.path().join(BACKUP_DIR), "vault.pwvault").unwrap();
        backups.sort_by_key(|(s, _)| *s);
        assert_eq!(backups.len(), MAX_BACKUPS, "备份数应被修剪到 MAX_BACKUPS");

        // 最旧的 seq 0、1 已被淘汰
        let min_seq = backups.first().unwrap().0;
        assert_eq!(min_seq, 2, "seq 0/1（最旧）应被淘汰");
        // 最新备份是倒数第二次写入的版本（最后一次写入留在主文件）
        let newest = backups.last().unwrap();
        assert_eq!(
            std::fs::read(&newest.1).unwrap(),
            format!("version-{}", writes - 2).as_bytes()
        );
    }

    #[test]
    fn backup_filenames_are_namespaced_per_vault() {
        let dir = temp_dir();
        let a = dir.path().join("work.pwvault");
        let b = dir.path().join("personal.pwvault");
        save_atomic(&a, b"a1").unwrap();
        save_atomic(&a, b"a2").unwrap();
        save_atomic(&b, b"b1").unwrap();
        save_atomic(&b, b"b2").unwrap();

        let backup_dir = dir.path().join(BACKUP_DIR);
        assert_eq!(list_backups(&backup_dir, "work.pwvault").unwrap().len(), 1);
        assert_eq!(
            list_backups(&backup_dir, "personal.pwvault").unwrap().len(),
            1
        );
    }
}
