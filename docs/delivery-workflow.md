# Mudsnote 交付流程

Mudsnote 使用 Devflow 管理非简单修改：任务契约 → 独立 worktree → 验证 → Draft PR → CI → 合并后真实验收 → 清理。

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

PR CI 运行上下文预算、数据边界及对应平台构建；不访问 iCloud、Keychain、真实笔记、个人设置或凭证。真实数据、Widget、iCloud 和真机行为单独验收。

## 高效验证节奏

1. 完成一轮连贯修改后先运行 `git diff --check`。
2. 运行一次与改动直接相关的测试组。
3. 集中修复已知失败，再复测一次相关测试组。
4. 稳定候选只运行一次对应平台的最终 `pr` 或 `full` 验证。
5. `live` 只用于需要真实安装证据的稳定候选，不作为每个小补丁的反馈循环。

完整输出交给 Devflow 日志；当前上下文只保留摘要和失败证据。文档、handoff 与决策记录在核心实现稳定后集中更新，并遵循 `docs/ARCHITECTURE.md` 的单一事实源分工。

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
