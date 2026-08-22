# Mudsnote Notes

When working in this repo:

1. Before editing, inspect the branch, HEAD, and dirty state, then use
   `./scripts/agent_context.sh --list` and a focused topic route as needed.
2. Then run `./scripts/agent_context.sh <topic> [regex]` and expand only after a miss. Do not pre-read `README.md`, `docs/AI_HANDOFF.md`, Skill docs, memory, changelog, or historical tasks.
3. Load the owning document only when the capsule/code is insufficient, a gate fails, rules conflict, or the task changes that process. Read `docs/ARCHITECTURE.md` only for boundary changes and `docs/delivery-workflow.md` only for delivery exceptions.
4. `CHANGELOG.md` is user-visible history, not the only technical truth.
5. Quick-capture UI may span `EditorWindowController.swift`, `Chrome/`, and `MarkdownRichEditor.swift`.
6. Declare `macos`, `ios`, or explicit `both`, then use `./scripts/verify <scope> pr|full|live`.
7. `both` requires an explicitly dual-platform request. iOS-only work must not package or install macOS.
8. Local AppKit/UI fixes use the project route and real-window verification; do not invoke Product Design unless the user requests it or the task requires visual reproduction from a reference.

## Token-efficient repository workflow

1. Expand search from routed file to module to repository only after a miss.
2. Locate symbols first; read at most about 200 nearby lines and do not reread unchanged ranges.
3. After editing, use a focused `git diff --unified=3` and a concise confirmed-facts summary.
4. Test one coherent patch: focused run, at most one corrective rerun, then final verification.
5. Put independent models, projections, services, and reusable views in focused files.
6. Update only the document that owns a stable fact, after implementation is stable.

## Documentation ownership

- `ARCHITECTURE`: stable boundaries; `AI_HANDOFF`: current constraints; `CHANGELOG`: user-visible history.
- `agent-memory/decisions/` and `incidents/`: rationale and failures. Never copy iteration logs into handoff.

Delivery follows `/Users/Donald/Code/AGENTS.md` and the project checks below.
Mudsnote adds only these project checks:

- `./scripts/verify pr|full` detects a single-platform diff; `live` always
  requires explicit `macos` or `ios`.
- Never run the other platform's installation as incidental verification;
  worktrees share `/Applications/Mudsnote.app` and the connected iPhone.
- CI must not access iCloud, Keychain, real note folders, personal settings,
  credentials, or other user data.
- Keep UI tuning in one task until stable. Install a reversible candidate only
  when the user needs local experience.
