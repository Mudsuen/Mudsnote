# Mudsnote Notes

When working in this repo:

1. Read `README.md` first.
2. Before substantial work, read `docs/AI_HANDOFF.md`; use `agent-memory/START_HERE.md` before deeper memory.
3. Run `./scripts/agent_context.sh <topic> [regex]`; read `docs/ARCHITECTURE.md` only for boundary changes.
4. `CHANGELOG.md` is user-visible history, not the only technical truth.
5. Quick-capture UI may span `EditorWindowController.swift`, `Chrome/`, and `MarkdownRichEditor.swift`.
6. Declare `macos`, `ios`, or explicit `both`, then use `./scripts/verify <scope> pr|full|live`.
7. Start platform tasks with `--track macos` or `--track ios`; resolve baseline/PR overlap before development.
8. `both` requires an explicitly dual-platform request. iOS-only work must not package or install macOS.

## Token-efficient repository workflow

1. Expand search from routed file to module to repository only after a miss.
2. Locate symbols first; read at most about 200 nearby lines and do not reread unchanged ranges.
3. After editing, use a focused `git diff --unified=3` and a ≤12-line confirmed-facts summary.
4. Test one coherent patch: focused run, at most one corrective rerun, then final verification.
5. Put independent models, projections, services, and reusable views in focused files.
6. Update only the document that owns a stable fact, after implementation is stable.

## Documentation ownership

- `ARCHITECTURE`: stable boundaries; `AI_HANDOFF`: current constraints; `CHANGELOG`: user-visible history.
- `agent-memory/decisions/` and `incidents/`: rationale and failures. Never copy iteration logs into handoff.

## Delivery

- Follow `/Users/Donald/Code/Devflow/README.md` and use `/Users/Donald/Code/Devflow/bin/devtask`.
- Devflow may continue to call `./scripts/verify pr|full`; the dispatcher detects a single-platform diff and delegates only to that platform. Documentation-only changes run policy checks without building either app.
- `live` always requires an explicit platform argument or `MUDSNOTE_PLATFORM_SCOPE`; it never infers an installation target.
- Concurrent worktrees share `/Applications/Mudsnote.app` and the connected iPhone, so never run another platform's live flow as incidental verification.
- PR CI must not access iCloud, Keychain, real note folders, personal settings, credentials, or other user data.
