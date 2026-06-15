# PwVault

PwVault 是一个本地优先的私人密码管理器。项目目标是把账号密码保存在本地加密库文件中，通过 Rust 实现核心加密与存储逻辑，通过 Flutter 提供 Windows、macOS、iOS 等平台的客户端界面。

当前仓库仍处于早期开发阶段：加密核心、存储层、FFI 接口和 Dart 服务层已打通，Flutter UI 还主要是解锁页与主界面占位。

## 项目目标

- 本地优先：离线可用，同步不是使用前提。
- 零知识加密：主密码不落盘，库文件离开主密码不可解密。
- 跨平台客户端：优先支持 Windows、macOS、iOS，后续可按需扩展 Linux。
- 可维护核心：密码学、持久化和合并逻辑集中在 Rust 层，Flutter 负责交互和状态管理。

完整产品设计文档见 [docs/password-manager-pdr.html](docs/password-manager-pdr.html)。

## 目录结构

```text
.
├── app/                 # Flutter 客户端
│   ├── lib/             # UI、路由、服务层、FRB bridge
│   ├── test/            # Flutter/Dart 单元测试
│   └── rust_builder/    # Flutter Rust Bridge 构建辅助
├── core_crypto/         # Rust 加密与保险库核心
│   ├── src/             # KDF、加密、容器、SQLite 存储、FFI API
│   ├── migrations/      # 内存 SQLite schema
│   └── tests/           # Rust 集成测试
├── docs/                # 产品/设计文档
└── .github/workflows/   # CI
```

## 当前能力

### Rust 核心

- 保险库创建、解锁、锁定和修改主密码。
- AES-256-GCM 字段级加密，Argon2id 主密码派生。
- 随机 DEK + KEK 包裹模型；改主密码只重新包裹 DEK，不重加密条目。
- 自定义 `.pwvault` 容器格式，原子写入和滚动备份。
- 内存 SQLite 存储，序列化后写入加密容器 body。
- 条目 CRUD、元数据列表、按需解密密码、完整明文读取、软删除和恢复。
- `flutter_rust_bridge` FFI API，向 Dart 暴露 `VaultHandle`、`EntryDraft`、`EntryMeta`。
- 简单 CLI smoke test 入口。

### Flutter 客户端

- Flutter 应用骨架、路由、浅色/深色主题。
- Riverpod 状态管理。
- Rust bridge 初始化和连通性探针。
- `VaultService` 封装建库/解锁/条目操作/改密/锁定，并把 Rust 错误映射为 Dart 领域异常。
- 自动锁定服务，默认 5 分钟无活动后锁定。
- 剪贴板密码复制后自动清理，默认 30 秒。
- 条目搜索索引，支持标题、用户名、URL、标签和中文拼音/首字母匹配。
- 密码/口令生成服务，支持 Rust CSPRNG 生成与 Dart 侧强度评估。
- 静态解锁页 UI：库选择器、主密码输入、眼睛切换和提示文案。
- 桌面主界面 Shell：三栏布局、侧边栏折叠、mock 列表与详情面板。
- 列表栏搜索交互：150ms debounce 实时过滤、Esc 清空、命中高亮、拼音匹配标注与空态引导新建（基于 mock 数据）。
- 详情面板：通用 FieldRow 组件、密码行状态机（掩码 8 点↔明文 10s 倒计时回隐、切后台/锁定立即回隐、明文按需解密回隐后引用置空）、复制反馈倒计时条（基于 mock 数据）。
- 条目编辑：新建/编辑表单（标题必填、标签多选、URL 规范化、脏数据关闭二次确认）、内嵌密码生成器（长度/字符集/短语模式 + zxcvbn 强度条）、保存写入共享 mock 存储后列表即时刷新。
- 全局快捷键：Ctrl/Cmd+F 聚焦搜索、Ctrl/Cmd+L 锁定、Ctrl/Cmd+N 新建、Enter 复制选中条目密码、↑↓ 列表导航（搜索/选中状态已提到共享 provider）。

### CI

GitHub Actions 已配置：

- Windows：`cargo test`、`flutter analyze`、`flutter test`、`flutter build windows --debug`
- macOS：`cargo test`、`flutter test`、`flutter build macos --debug`
- iOS simulator：`flutter build ios --simulator`

## 开发进度

当前开发已推进到 **M2 桌面 MVP 的 T2.12：设置页**，M2 的桌面 UI 任务（T2.6–T2.12）至此全部落地。下一步转入业务接通：真实解锁流程与把列表/详情/编辑的 mock 数据替换为真实库 CRUD。T2.12 接通了主题/自动锁定时长/剪贴板清除时长三项内存 provider（当前会话即时生效，落盘持久化留待后续），修改主密码经 zxcvbn 强度门槛校验后改密并立即锁定、退回解锁页。

进度维护约定：后续每完成、提交或合并一个开发任务，都必须同步更新本节的当前进度、任务表和“下一步”列表，确保 README 始终反映主线最新状态。

| 任务 | 状态 | 最近提交 | 说明 |
| --- | --- | --- | --- |
| T0.1 Flutter 工程脚手架 | 已完成 | `da8f3a8` | 三端 target、Riverpod、go_router 和目录骨架。 |
| T0.2 Rust/FRB 接线 | 已完成 | `211cd14` | `core_crypto` crate 与 Flutter Rust Bridge 打通 `ping()`。 |
| T0.3 CI | 已完成 | `d6ba011`, `65dea80` | Windows/macOS/iOS simulator CI 建立，并修正 analyze 配置。 |
| T1.1 KDF + 机密类型 | 已完成 | `0f018ce` | Argon2id、`SecretString`/`SecretBytes`、zeroize。 |
| T1.2 AES-GCM 字段加密 | 已完成 | `cf5dbd8` | AES-256-GCM seal/open 与 AAD 绑定。 |
| T1.3 容器格式 | 已完成 | `2e1a136` | `.pwvault` 容器格式与 Header AAD 防篡改。 |
| T1.4 库生命周期 | 已完成 | `6390cd5` | create/unlock/lock/change_password。 |
| T1.5 内存 SQLite 存储 | 已完成 | `f9ad688`, `eca894c` | 字段级加解密 CRUD，并完成代码审查修复。 |
| T1.6 原子持久化 | 已完成 | `2fa31d0` | `persist.rs` 原子写入与 `backups/` 滚动 20 版。 |
| T1.7 Session + CLI | 已完成 | `5141e68` | 整合层、`pwv` 开发 CLI 和全流程冒烟测试。 |
| T1.8 FFI bridge | 已完成 | `bdf30ee` | `VaultHandle` 生命周期和条目 CRUD 暴露给 Dart，M1 加密内核收官。 |
| T2.1 VaultService | 已完成 | `fc80056` | Dart bridge 包装、Riverpod providers、领域异常。 |
| T2.2 SearchIndexService | 已完成 | `2436249`, `cd91f55` | 拼音/首字母搜索、多关键词匹配、排序与验证修复。 |
| T2.3 AutoLockService | 已完成 | `6c235c3` | 空闲计时和超时锁定服务。 |
| T2.4 ClipboardService | 已完成 | `6e8bce3` | 复制密码后定时清理，清理前校验剪贴板内容是否被用户覆盖。 |
| T2.5 PasswordGeneratorService | 已完成 | `22ba2f9` | Rust CSPRNG 密码/短语生成、Dart 服务封装、zxcvbn 强度评估已接入。 |
| T2.6 解锁页 | 已完成（静态 UI） | `2905611` | 库选择器、主密码框、眼睛切换和提示文案已实现；真实解锁和错误等待后续接入。 |
| T2.7 桌面三栏主界面 | 已完成（Shell） | `673754d` | 侧边栏 140px、列表栏 220px、详情区自适应；窄屏折叠侧边栏为汉堡抽屉；暗色主题适配。 |
| T2.8 列表栏搜索与结果交互 | 已完成（mock） | `421f297` | 搜索框 150ms debounce、Esc 清空、命中高亮、拼音匹配标注、空态引导新建；数据仍为 mock。 |
| T2.9 详情面板与密码行状态机 | 已完成（mock） | `40271e3` | 通用 FieldRow、密码行状态机（8 点掩码↔明文 10s 倒计时回隐、切后台/锁定立即回隐、引用置空）、复制反馈倒计时条；明文解密为 mock。 |
| T2.10 条目编辑与密码生成器 | 已完成（mock） | `eb94323` | 新建/编辑表单（标题必填、标签多选、URL 规范化、脏数据二次确认）、内嵌生成器（长度/字符集/短语+强度条）、共享 mock 存储保存后列表即时刷新。 |
| T2.11 全局快捷键 | 已完成（mock） | `2b55cb2` | Ctrl/Cmd+F 搜索、Ctrl/Cmd+L 锁定、Ctrl/Cmd+N 新建、Enter 复制选中密码、↑↓ 导航；`core/shortcuts.dart` + 列表状态 provider 化，五组快捷键 widget test 全过。 |
| T2.12 设置页 | 已完成 | `<pending>` | `features/settings/`：主题（系统/浅色/深色）、自动锁定时长、剪贴板清除时长接通既有内存 provider；修改主密码经 zxcvbn 强度门槛（score≥3）+ 当前密码校验，改密后立即锁定退回解锁页；侧边栏/AppBar 设置入口；7 项 widget test 全过。落盘持久化留待后续。 |
| T3+ 移动端、同步、导入导出、发布 | 未开始 | - | PDR 中已有规划，代码层暂未实现。 |

## 本地开发

### 环境要求

- Flutter 3.44.1 或与 `app/pubspec.yaml` 兼容的稳定版本
- Rust stable toolchain
- Windows/macOS/iOS 平台构建所需的本机工具链

### 获取依赖

```bash
cd app
flutter pub get
```

Rust 依赖会在构建或测试时由 Cargo 拉取：

```bash
cargo test --manifest-path core_crypto/Cargo.toml
```

### 运行测试

```bash
cargo test --manifest-path core_crypto/Cargo.toml

cd app
flutter analyze
flutter test
```

### 运行客户端

```bash
cd app
flutter run -d macos
```

也可以把 `macos` 换成当前机器可用的 Flutter 设备，例如 `windows` 或 iOS simulator。

## 下一步

1. 实现真实解锁流程：库文件选择、创建库、输入主密码、错误提示和递增等待。
2. 把列表/详情/编辑的 mock 数据替换为真实库 CRUD，并接通选中条目→详情。
3. 把设置页的主题/时长偏好与修改主密码接入真实持久化（落盘，与库内 meta 协调）。
4. 设计并实现同步/合并流程。
5. 补齐 TOTP、导入导出和发布打包。

## 安全说明

PwVault 仍在开发中，尚未经过第三方安全审计。当前代码适合开发和验证，不建议存放真实高价值密码。
