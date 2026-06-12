-- PwVault schema v1（PDR 第 5 章）
-- 全部业务字段为 AES-256-GCM 密文 blob（nonce‖ct‖tag，AAD={entry_id}:{field}）；
-- 时间戳 / rev / favorite / deleted_at 为同步所需的低敏感明文元数据。

CREATE TABLE entries (
    id          TEXT PRIMARY KEY,           -- UUIDv7，时间有序
    title_ct    BLOB NOT NULL,
    username_ct BLOB NOT NULL,
    password_ct BLOB NOT NULL,
    url_ct      BLOB NOT NULL,
    notes_ct    BLOB NOT NULL,
    totp_ct     BLOB,                       -- otpauth URI 密文，可空
    tags_ct     BLOB NOT NULL,              -- JSON 数组密文
    favorite    INTEGER NOT NULL DEFAULT 0, -- 常用标记（0/1）
    created_at  INTEGER NOT NULL,           -- Unix ms
    updated_at  INTEGER NOT NULL,           -- Unix ms
    deleted_at  INTEGER,                    -- 软删除墓碑（Unix ms），同步需要
    rev         TEXT NOT NULL               -- "device_id:counter"，冲突检测用
);

CREATE INDEX idx_entries_deleted ON entries(deleted_at);
CREATE INDEX idx_entries_updated ON entries(updated_at); -- list/search 按 updated_at 排序

-- 库级配置（PDR 5.3），value 为密文（AAD=meta:{key}:value）
CREATE TABLE meta (
    key      TEXT PRIMARY KEY,
    value_ct BLOB NOT NULL
);

-- 密码历史（PDR 5.2，T5.4 启用；schema 先行）
-- id 为 UUIDv7 主键，同时是 AAD 身份：password_ct 的 AAD 必须为
-- ("history", id, "password")，与现役 entries.password_ct 的
-- ("entry", entry_id, "password") 域隔离，防历史密文移植回现役槽位。
CREATE TABLE password_history (
    id          TEXT PRIMARY KEY,
    entry_id    TEXT NOT NULL REFERENCES entries(id),
    password_ct BLOB NOT NULL,
    replaced_at INTEGER NOT NULL
);

CREATE INDEX idx_history_entry ON password_history(entry_id);
