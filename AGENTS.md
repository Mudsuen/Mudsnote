# Mudsnote Notes

## Routing

- Start with `./scripts/agent_context.sh --list`, then run
  `./scripts/agent_context.sh <topic> [regex]` and expand only after a miss.
- Load the owning document only when routed context and code are insufficient,
  a gate fails, rules conflict, or the task changes that process. Read
  `docs/ARCHITECTURE.md` only for boundary changes and
  `docs/delivery-workflow.md` only for delivery exceptions.
- Quick-capture UI may span `EditorWindowController.swift`, `Chrome/`, and
  `MarkdownRichEditor.swift`.

## Platform and Verification

- Declare `macos`, `ios`, or explicit `both`, then run
  `./scripts/verify <scope> pr|full|live`. `both` requires an explicitly
  dual-platform request.
- `./scripts/verify pr|full` detects a single-platform diff; `live` always
  requires explicit `macos` or `ios`.
- Never build or install the other platform as incidental verification;
  worktrees share `/Applications/Mudsnote.app` and the connected iPhone.
- CI must not access iCloud, Keychain, real note folders, personal settings,
  credentials, or other user data.
- Verify local AppKit/UI fixes in a real window. Use Product Design only when
  requested or when reproducing a visual reference.
- For iOS installation, require signing and a tested recovery path that
  protects the working app.

## Documentation

- `ARCHITECTURE` owns stable boundaries, `AI_HANDOFF` current constraints, and
  `CHANGELOG` user-visible history.
- Keep rationale and recoverable failures in `agent-memory/decisions/` and
  `agent-memory/incidents/`; do not copy iteration logs into handoff.
