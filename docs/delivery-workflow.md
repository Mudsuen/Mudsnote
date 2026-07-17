# Mudsnote 交付流程

Mudsnote 使用 Devflow 管理非简单修改：任务契约 → 独立分支/worktree → 本地验证 → Draft PR → CI → 合并后真实验收 → 最终确认后清理。

## 三层验证

- `./scripts/verify pr`：运行确定性 Swift 测试和数据边界检查。共享 runner 上容易抖动的墙钟性能门禁不阻塞 PR。
- `./scripts/verify full`：Release 构建和包括严格性能门禁在内的完整测试，适合固定本机或合并后运行。
- `./scripts/verify live`：打包、签名、安装并打开 `/Applications/Mudsnote.app`，仅限明确的本地真实验收。

PR CI 只有 `policy` 与 `build-and-test` 两项稳定检查，不访问 iCloud、Keychain、真实笔记目录、个人设置或凭证。真实笔记、分享入口、Widget、iCloud 和真机行为必须单独人工确认。

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
