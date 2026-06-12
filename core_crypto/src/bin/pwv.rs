//! pwv — core_crypto 开发 CLI（T1.7）。仅用于本地冒烟与手测，不分发。
//!
//! 主密码经环境变量传入（便于脚本化，避免出现在进程参数里）：
//!   PWV_PASSWORD       主密码（所有命令）
//!   PWV_NEW_PASSWORD   chpass 的新密码
//!   PWV_KDF_FAST=1     create 用低成本 KDF（加速测试，勿用于真实库）
//!
//! 命令：
//!   pwv create <path>
//!   pwv unlock <path>
//!   pwv add    <path> --title T [--username U --password P --url X --notes N --tags a,b --totp URI --favorite]
//!   pwv list   <path>
//!   pwv show   <path> <id>
//!   pwv chpass <path>

use std::process::ExitCode;

use core_crypto::kdf::KdfParams;
use core_crypto::secret::SecretString;
use core_crypto::session::Session;
use core_crypto::store::EntryPlain;

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("error: {e}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> Result<(), String> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let cmd = args.first().map(String::as_str).unwrap_or("");
    let rest = if args.is_empty() { &[][..] } else { &args[1..] };
    match cmd {
        "create" => cmd_create(rest),
        "unlock" => cmd_unlock(rest),
        "add" => cmd_add(rest),
        "list" => cmd_list(rest),
        "show" => cmd_show(rest),
        "chpass" => cmd_chpass(rest),
        "" => Err(usage()),
        other => Err(format!("未知命令 {other:?}\n{}", usage())),
    }
}

fn usage() -> String {
    "用法: pwv <create|unlock|add|list|show|chpass> <path> [..]".into()
}

fn cmd_create(args: &[String]) -> Result<(), String> {
    let path = positional(args, 0)?;
    let pw = password()?;
    let kdf = if env_flag("PWV_KDF_FAST") {
        Some(fast_kdf()?)
    } else {
        None
    };
    let s = Session::create(&path, &pw, kdf).map_err(de)?;
    println!("created {path} (device {})", s.device_id());
    Ok(())
}

fn cmd_unlock(args: &[String]) -> Result<(), String> {
    let path = positional(args, 0)?;
    let s = Session::unlock(&path, &password()?).map_err(de)?;
    println!(
        "unlocked {path} ({} entries)",
        s.list_meta().map_err(de)?.len()
    );
    Ok(())
}

fn cmd_add(args: &[String]) -> Result<(), String> {
    let path = positional(args, 0)?;
    let mut s = Session::unlock(&path, &password()?).map_err(de)?;
    let entry = EntryPlain {
        id: None,
        title: flag(args, "--title").ok_or("缺少 --title")?,
        username: flag(args, "--username").unwrap_or_default(),
        password: SecretString::new(flag(args, "--password").unwrap_or_default()),
        url: flag(args, "--url").unwrap_or_default(),
        notes: flag(args, "--notes").unwrap_or_default(),
        totp_uri: flag(args, "--totp").map(SecretString::new),
        tags: flag(args, "--tags")
            .map(|s| s.split(',').map(str::to_string).collect())
            .unwrap_or_default(),
        favorite: has_flag(args, "--favorite"),
    };
    let meta = s.upsert(entry).map_err(de)?;
    // 仅打印 id，便于脚本捕获
    println!("{}", meta.id);
    Ok(())
}

fn cmd_list(args: &[String]) -> Result<(), String> {
    let path = positional(args, 0)?;
    let s = Session::unlock(&path, &password()?).map_err(de)?;
    for m in s.list_meta().map_err(de)? {
        let totp = if m.has_totp { " [TOTP]" } else { "" };
        let fav = if m.favorite { " ★" } else { "" };
        println!(
            "{}\t{}\t{}\t{}{totp}{fav}",
            m.id, m.title, m.username, m.url
        );
    }
    Ok(())
}

fn cmd_show(args: &[String]) -> Result<(), String> {
    let path = positional(args, 0)?;
    let id = positional(args, 1)?;
    let s = Session::unlock(&path, &password()?).map_err(de)?;
    let e = s.get_full(&id).map_err(de)?;
    println!("id:       {id}");
    println!("title:    {}", e.title);
    println!("username: {}", e.username);
    println!("password: {}", e.password.expose());
    println!("url:      {}", e.url);
    println!("notes:    {}", e.notes);
    println!("tags:     {}", e.tags.join(","));
    if let Some(t) = &e.totp_uri {
        println!("totp:     {}", t.expose());
    }
    Ok(())
}

fn cmd_chpass(args: &[String]) -> Result<(), String> {
    let path = positional(args, 0)?;
    let old = password()?;
    let new = env_secret("PWV_NEW_PASSWORD")?;
    let mut s = Session::unlock(&path, &old).map_err(de)?;
    s.change_password(&old, &new).map_err(de)?;
    println!("ok");
    Ok(())
}

// ---- 辅助 ----

fn positional(args: &[String], i: usize) -> Result<String, String> {
    args.iter()
        .filter(|a| !a.starts_with("--"))
        .nth(i)
        .cloned()
        .ok_or_else(|| format!("缺少第 {} 个位置参数", i + 1))
}

fn flag(args: &[String], name: &str) -> Option<String> {
    args.iter()
        .position(|a| a == name)
        .and_then(|i| args.get(i + 1))
        .cloned()
}

fn has_flag(args: &[String], name: &str) -> bool {
    args.iter().any(|a| a == name)
}

fn env_flag(name: &str) -> bool {
    std::env::var(name).is_ok_and(|v| v == "1")
}

fn password() -> Result<SecretString, String> {
    env_secret("PWV_PASSWORD")
}

fn env_secret(name: &str) -> Result<SecretString, String> {
    std::env::var(name)
        .map(SecretString::new)
        .map_err(|_| format!("缺少环境变量 {name}"))
}

fn fast_kdf() -> Result<KdfParams, String> {
    let mut p = KdfParams::generate().map_err(de)?;
    p.m_kib = 8 * 1024;
    p.t_cost = 1;
    Ok(p)
}

fn de<E: std::fmt::Display>(e: E) -> String {
    e.to_string()
}
