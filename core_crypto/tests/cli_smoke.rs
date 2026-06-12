//! pwv CLI 全流程冒烟测试（T1.7 验收）。
//! 经 CARGO_BIN_EXE_pwv 调用真实二进制，覆盖建库→解锁→增→列→看→改密
//! →旧密码失效→新密码可用且数据完整的完整链路。

use std::process::{Command, Output};

const BIN: &str = env!("CARGO_BIN_EXE_pwv");

fn pwv(args: &[&str], envs: &[(&str, &str)]) -> Output {
    let mut c = Command::new(BIN);
    c.args(args);
    // 清掉可能从外部继承的相关变量，保证用例自洽
    c.env_remove("PWV_PASSWORD")
        .env_remove("PWV_NEW_PASSWORD")
        .env_remove("PWV_KDF_FAST");
    for (k, v) in envs {
        c.env(k, v);
    }
    c.output().expect("运行 pwv 失败")
}

fn stdout(o: &Output) -> String {
    String::from_utf8_lossy(&o.stdout).into_owned()
}

fn stderr(o: &Output) -> String {
    String::from_utf8_lossy(&o.stderr).into_owned()
}

#[test]
fn full_cli_flow() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("vault.pwvault");
    let path = path.to_str().unwrap();

    let master = &[("PWV_PASSWORD", "master"), ("PWV_KDF_FAST", "1")][..];

    // create
    let o = pwv(&["create", path], master);
    assert!(o.status.success(), "create 失败: {}", stderr(&o));
    assert!(stdout(&o).contains("created"));

    // unlock 成功
    let o = pwv(&["unlock", path], master);
    assert!(o.status.success(), "unlock 失败: {}", stderr(&o));
    assert!(stdout(&o).contains("0 entries"));

    // 错误密码失败
    let o = pwv(&["unlock", path], &[("PWV_PASSWORD", "wrong")]);
    assert!(!o.status.success(), "错误密码竟然解锁成功");

    // 缺少密码环境变量失败
    let o = pwv(&["unlock", path], &[]);
    assert!(!o.status.success());
    assert!(stderr(&o).contains("PWV_PASSWORD"));

    // add
    let o = pwv(
        &[
            "add",
            path,
            "--title",
            "淘宝",
            "--username",
            "owen@163.com",
            "--password",
            "kQ9#mTr2!vLp",
            "--url",
            "taobao.com",
            "--totp",
            "otpauth://totp/x?secret=ABC",
            "--tags",
            "个人,购物",
            "--favorite",
        ],
        master,
    );
    assert!(o.status.success(), "add 失败: {}", stderr(&o));
    let id = stdout(&o).trim().to_string();
    assert!(!id.is_empty(), "add 应输出条目 id");

    // list 含标题、id、TOTP、收藏标记
    let o = pwv(&["list", path], master);
    let out = stdout(&o);
    assert!(out.contains("淘宝"), "list 缺标题: {out}");
    assert!(out.contains(&id));
    assert!(out.contains("[TOTP]"));
    assert!(out.contains('★'));

    // show 含密码明文与 TOTP
    let o = pwv(&["show", path, &id], master);
    let out = stdout(&o);
    assert!(out.contains("kQ9#mTr2!vLp"), "show 缺密码: {out}");
    assert!(out.contains("淘宝"));
    assert!(out.contains("otpauth://totp/x?secret=ABC"));
    assert!(out.contains("个人,购物"));

    // chpass: master -> master2
    let o = pwv(
        &["chpass", path],
        &[
            ("PWV_PASSWORD", "master"),
            ("PWV_NEW_PASSWORD", "master2"),
            ("PWV_KDF_FAST", "1"),
        ],
    );
    assert!(o.status.success(), "chpass 失败: {}", stderr(&o));

    // 旧密码失效
    let o = pwv(&["unlock", path], master);
    assert!(!o.status.success(), "改密后旧密码仍能解锁");

    // 新密码可用且数据完整
    let o = pwv(&["unlock", path], &[("PWV_PASSWORD", "master2")]);
    assert!(o.status.success(), "新密码解锁失败: {}", stderr(&o));
    let o = pwv(&["list", path], &[("PWV_PASSWORD", "master2")]);
    assert!(stdout(&o).contains("淘宝"), "改密后数据丢失");

    // show 仍可取出原密码
    let o = pwv(&["show", path, &id], &[("PWV_PASSWORD", "master2")]);
    assert!(stdout(&o).contains("kQ9#mTr2!vLp"));
}
