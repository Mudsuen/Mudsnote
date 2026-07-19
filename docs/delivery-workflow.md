# Mudsnote 交付流程

Mudsnote 使用 Devflow 管理非简单修改：任务契约 → 独立分支/worktree → 本地验证 → Draft PR → CI → 合并后真实验收 → 最终确认后清理。

## 平台范围

每个任务先声明 `macos`、`ios` 或明确的 `both`，再选择验证层级：

- `./scripts/verify macos pr|full|live`：只构建、测试或安装 macOS；`live` 安装 `/Applications/Mudsnote.app`。
- `./scripts/verify ios pr|full|live`：只构建、测试或安装 iOS；`live` 使用真机流程，不触碰 macOS 安装包。
- `./scripts/verify both pr|full|live`：仅用于用户明确要求双端的任务；按 macOS、iOS 顺序执行。

Devflow 的单参数 `./scripts/verify pr|full` 会从任务 diff 自动识别单端范围；文档任务只执行策略检查。`./scripts/verify live` 不推断目标并直接拒绝，必须明确平台。

## 三层验证

- `pr`：该平台的确定性构建/测试和数据边界检查。
- `full`：该平台的 Release 构建与完整测试。
- `live`：该平台的真实安装验收，仅限本地且必须显式声明平台。

PR CI 只有 `policy` 与 `build-and-test` 两项稳定检查；`build-and-test` 由 dispatcher 根据改动路径只进入对应平台。CI 不访问 iCloud、Keychain、真实笔记目录、个人设置或凭证。真实笔记、分享入口、Widget、iCloud 和真机行为必须单独人工确认。

## 日常最小操作

```bash
devtask start Mudsnote <slug> --risk <low|medium|high> ...
# 在输出的 worktree 中开发并提交
devtask pr Mudsnote <任务ID> --title "<PR 标题>"
# 合并并完成 full/live 后
devtask accept Mudsnote <任务ID> --note "<验收证据>"
devtask cleanup Mudsnote <任务ID> --confirm <任务ID> --dry-run
```

若本地 `main` 与 `origin/main` 不一致，先核实差异。只有确认任务应故意从远端基线开始时，才使用 `--allow-remote-base`。
