# STATUS

[English](../en/STATUS.md) · [中文](STATUS.md)

截至 **2026-11-11**（Asia/Shanghai）。

**过期即失效：这份文件只记录写下这一刻的事实。** 接手前先运行 `git log -1` 与
`swift test --disable-sandbox`，再按「最后一次验证」重跑相关命令；当前输出与本文不一致时，
以当前输出为准并更新本文。

## 当前代码状态

- 代码 HEAD：`335211b`（`chore: release v2.3.3`），`origin/main` 也指向 `335211b`。
  Xcode 工程与本地 Debug／Release 两种构建的版本均为 **2.3.3 (build 233)**。
- 本地标签：`v2.1.0`、`v2.3.0`、`v2.3.1`、`v2.3.2`、`v2.3.3`。
- 本文所在工作树为 `agent/whole-project-audit`，包含全项目审计的未提交源码、测试与文档修复。
  主工作树另有未提交的共享契约修复：`.github/workflows/ci.yml`、`AGENTS.md` 与
  `scripts/{Info.plist,backup_app.sh,build_release.sh,publish_release.sh}`。完整的审计结果由这两组改动组成。
- 设置 schema：**12**。v11 添加 `karabinerPanelSignalEnabled`（默认 `true`）；v12 添加
  `autoAuditUnreachableShortcuts`（默认 `true`）。旧文件缺少这些键时直接采用默认值。
  `usage.json` 的独立 schema 为 **1**，菜单缓存 schema 为 **6**。
- `/Applications/Kaname.app` 的 Info.plist 读取结果为 **2.3.3 (232)**，
  `KanameCommit=335211b`。本轮只读取这些元数据，没有替换或重启安装包。

## 当前审计改动

### 已修源码与测试

- 搜索回退只有在注入结果为 `.sent` 后才记录用量；失败与取消不再增加统计。
- 系统热键或配置扫描结果更新后，已打开的面板与搜索会刷新；App 启动或退出也会刷新运行中 App
  范围及冲突扫描所使用的目录。
- 未成功启动的第二个实例直接结束自己的 `stop()`，不会清除正在运行实例写入的 Karabiner 变量。
- 被吞掉的物理按键按 key code 分别追踪；面板捕获规则消失后，原按键的自动重复仍被消费，直到对应
  key-up。一个键的松开不会清除另一个键的吞键状态。
- 面板与搜索在异步 AX 工作之前捕获执行目标。注入现在要求显式目标，在激活或投递前预检完整 chord，
  按顺序解析 `KeyStep.alternates`；任一步无法映射都会拒绝整份计划。
- 界面、注入与光标恢复工作均有会话所有权。替换或关闭界面会使旧的异步完成失效；光标恢复可以跨越
  面板／搜索切换，同时拒绝过期完成移动指针。
- 工程 build 号从 232 升至 **233**，marketing version 保持 2.3.3。SwiftPM 保留
  `swift-tools-version: 6.0` 与 Swift 6.1 CI 兼容性；XCTest 宿主显式标为 `nonisolated`，不依赖
  仅 Swift 6.2 可用的默认隔离 manifest 设置。
- 测试中的并发 token 收集改为锁保护。回归测试现覆盖独立吞键、完整注入计划解析与会话所有权。

### 已修共享脚本与 CI

- Release CI 的 `xcodebuild | tail` 管道启用 `pipefail`，构建失败会向 CI 传播。
- 发布脚本拒绝发布「现有标签指向的 commit 与 DMG 构建 commit 不同」的资产；匹配标签的重试会从
  上一个发布标签生成变更说明。
- `Kaname Local` 签名的 DMG 不请求 Apple 时间戳；Developer ID 签名仍使用时间戳。
- 备份 dry-run 按备份后的数量预测清理结果；回退构建 plist 模板更新为 2.3.3 / **233**。

### 文档边界

- README、架构、FAQ、权限、故障排查、发布说明与 STATUS 的当前行为描述以代码为准，中英文成对更新。
- 明确标注为历史记录、开发过程或某个旧版本发布说明的内容保留其时间语境；其中只修正链接、
  路径及可由 git 历史直接证实的错误。
- 用户可见修复汇总在根目录 `CHANGELOG.md` 的 `[Unreleased]`。

## 最后一次验证

以下结果来自 2026-11-10 至 2026-11-11 在当前未提交源码上实际运行的检查。

| 检查 | 结果 |
| --- | --- |
| `git rev-parse --short HEAD` / `origin/main` | 均为 `335211b` |
| 已安装 Info.plist | `2.3.3` / `232` / `KanameCommit=335211b` |
| `swift test --disable-sandbox --enable-code-coverage` | **933 tests, 0 failures**；剪贴板契约测试出现一条 `sandbox_extension_consume failed: 1 (Operation not permitted)` 环境信息，该测试与整套测试均通过 |
| `Core/Pure` 行覆盖，使用 CI 的 `llvm-cov report/export` 命令 | **88.59%**；CI 门槛为 70% |
| `xcodebuild -project Kaname.xcodeproj -scheme Kaname -configuration Debug -derivedDataPath build/audit-debug CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build` | `BUILD SUCCEEDED` |
| 同一构建命令改用 `-configuration Release -derivedDataPath build/audit-release`，并经 `set -o pipefail` 与 `tail` | `BUILD SUCCEEDED` |
| 源码模板、Debug 与 Release Info.plist | `plutil -lint` 均通过；三者均为 2.3.3 / 233 |
| 修改过的 shell 脚本 | `bash -n` 通过 |
| 备份 dry-run 一次性夹具 | 保留期内预测不删除；达到及超过保留数时预测正确的最旧备份；目录保持原样 |
| 发布脚本一次性夹具 | commit 不匹配时退出 1；匹配标签重试生成 `Changes since v9.9.8`，不包含当前标签自身 |
| Markdown 相对链接 | 已检查目标存在；代码块与行内代码中的示例不当作链接 |
| `git diff --check` | 主工作树与审计工作树均通过 |

Debug/Release 构建日志中的 destination 选择与 AppIntents metadata 信息不是 Swift 编译警告；
两种配置都在 `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` 下完成。

## 剩余验证与设计事项

1. **实机交互验收。** VoiceOver、真实第二个实例、跨 Space 指针行为以及真实 AX／注入竞态仍需在
   运行中的安装包上做交互验证。
2. **事件 tap 恢复。** 恢复 backoff 当前配置仍为 `[0]`；调整它属于设计决策，需要单独做运行时验证。

## 环境与操作边界

- 沙箱内测试使用 `swift test --disable-sandbox`；缺少该参数时可能直接报
  `sandbox_apply: Operation not permitted`。
- `xcodebuild` 在嵌套沙箱中可能出现环境性失败；真伪以回退构建日志中的 `error:` 及沙箱外结果为准。
- 本轮没有执行提交、合并、推送、安装、签名、公证或发布，也没有修改 `/Applications`、备份目录或
  签名钥匙串。
- 大规模拆分与静态引用扫描得到的“死代码候选”不属于已验证修复；当前没有据此删除实现代码。
