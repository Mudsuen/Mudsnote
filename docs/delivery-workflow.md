# Mudsnote 交付流程

Mudsnote 使用 Devflow 管理非简单修改：任务契约 → 独立分支/worktree → 本地验证 → Draft PR → CI → 合并后真实验收 → 最终确认后清理。

长期商业化 Goal 只负责任务拆分和结果汇总。每项 Devflow 实现使用新的 Codex 任务，避免多日对话历史在每次测试轮询时重复进入上下文。

## 三层验证

- `./scripts/verify pr`：运行确定性 Swift 测试和数据边界检查。共享 runner 上容易抖动的墙钟性能门禁不阻塞 PR。
- `./scripts/verify full`：Release 构建和包括严格性能门禁在内的完整测试，适合固定本机或合并后运行。
- `./scripts/verify live`：打包、签名、安装并打开 `/Applications/Mudsnote.app`，仅限明确的本地真实验收。

PR CI 只有 `policy` 与 `build-and-test` 两项稳定检查，不访问 iCloud、Keychain、真实笔记目录、个人设置或凭证。真实笔记、分享入口、Widget、iCloud 和真机行为必须单独人工确认。

## iPhone 高效验证

同一任务始终复用 `.task/data/build-cache`，不要为每次重试创建新的 DerivedData：

```bash
./scripts/verify_ios unit
./scripts/verify_ios targeted MudsnoteCompanionUITests/MudsnoteCompanionUITests/testName
./scripts/verify_ios full
```

- 开发中运行单元测试和本次改动直接相关的定向 UI 测试。
- `full` 只在稳定候选版本的最终批次运行一次，不在每次补丁后重复执行。
- 长测试每 45–60 秒检查一次；成功只输出摘要，失败只输出失败附近内容，完整日志保存在 `.task/logs`。
- 一项任务尽量不超过三项紧密相关的验收行为；跨编辑器、存储、语音和阅读器等多个子系统时先拆分。

## 日常最小操作

```bash
devtask start Mudsnote <slug> --risk <low|medium|high> ...
# 在新的 Codex 任务中进入输出的 worktree，开发并提交
devtask pr Mudsnote <任务ID> --title "<PR 标题>"
# 合并并完成 full/live 后
devtask accept Mudsnote <任务ID> --note "<验收证据>"
devtask cleanup Mudsnote <任务ID> --confirm <任务ID> --dry-run
```

若本地 `main` 与 `origin/main` 不一致，先核实差异。只有确认任务应故意从远端基线开始时，才使用 `--allow-remote-base`。
