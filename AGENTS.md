# Mudsnote Notes

When working in this repo:

1. Read `README.md` first.
2. Read `docs/AI_HANDOFF.md` before substantial feature work, bugfixing, or UI changes.
3. Use `agent-memory/START_HERE.md` before opening deeper project memory or legacy `.codex` memory.
4. Treat `CHANGELOG.md` as user-visible iteration history, not as the only source of technical truth.
5. Use `docs/ARCHITECTURE.md` as the stable boundary map and run `./scripts/agent_context.sh <topic> [regex]` before opening source.
6. For quick-capture UI work, expect changes to span `EditorWindowController.swift`, `Chrome/`, and `MarkdownRichEditor.swift`.
7. Declare every implementation task as `macos`, `ios`, or explicitly `both` before validation.
8. Validate macOS work with `./scripts/verify macos pr|full|live`; prefer a packaged-app smoke over screenshot-only validation.
9. Validate iOS work with `./scripts/verify ios pr|full|live`; never run `package_app.sh` or mutate `/Applications/Mudsnote.app` from an iOS-only task.
10. Use `./scripts/verify both ...` only when the user request explicitly spans both platforms. A dual-platform live run is allowed to install both artifacts in sequence.

## Token-efficient repository workflow

1. Start in the routed files. Expand from one file to its module, then to the repository only after a miss.
2. In large files, use `rg -n` to locate a symbol and read no more than about 200 nearby lines at a time.
3. Do not reread an unchanged range. After editing, use `git diff --unified=3 -- <files>` as the working context.
4. Keep an internal confirmed-facts summary of no more than 12 lines; do not repeatedly reconstruct settled context.
5. Keep search expressions narrow. Prefer a symbol or behavior name over broad lists of UI terms.
6. Finish a coherent patch before testing: focused tests once, one corrective rerun if needed, then one final platform verification.
7. Update handoff, decisions, incidents, or user-visible history only after the implementation is stable and only when that file owns the fact.
8. A new independent model, projection, service, or reusable view belongs in a focused file; do not grow a large controller with an unrelated responsibility.

## Documentation ownership

- `docs/ARCHITECTURE.md`: stable boundaries and task routes.
- `docs/AI_HANDOFF.md`: compact current state and durable takeover constraints.
- `CHANGELOG.md`: user-visible iteration history.
- `agent-memory/decisions/` and `agent-memory/incidents/`: durable rationale and concrete failures.
- Do not duplicate chronological iteration summaries in `docs/AI_HANDOFF.md`.

## Delivery

- Follow `/Users/Donald/Code/Devflow/README.md` and use `/Users/Donald/Code/Devflow/bin/devtask`.
- Devflow may continue to call `./scripts/verify pr|full`; the dispatcher detects a single-platform diff and delegates only to that platform. Documentation-only changes run policy checks without building either app.
- `live` always requires an explicit platform argument or `MUDSNOTE_PLATFORM_SCOPE`; it never infers an installation target.
- Concurrent worktrees share `/Applications/Mudsnote.app` and the connected iPhone, so never run another platform's live flow as incidental verification.
- PR CI must not access iCloud, Keychain, real note folders, personal settings, credentials, or other user data.
