# Mudsnote Notes

When working in this repo:

1. In a Devflow worktree, start with `./scripts/agent_context.sh --task`; this JSON capsule is the default task context.
2. Then run `./scripts/agent_context.sh <topic> [regex]` and expand only after a miss. Do not pre-read `README.md`, `docs/AI_HANDOFF.md`, Skill docs, memory, changelog, or historical tasks.
3. Load the owning document only when the capsule/code is insufficient, a gate fails, rules conflict, or the task changes that process. Read `docs/ARCHITECTURE.md` only for boundary changes and `docs/delivery-workflow.md` only for delivery exceptions.
4. `CHANGELOG.md` is user-visible history, not the only technical truth.
5. Quick-capture UI may span `EditorWindowController.swift`, `Chrome/`, and `MarkdownRichEditor.swift`.
6. Declare `macos`, `ios`, or explicit `both`, then use `./scripts/verify <scope> pr|full|live`.
7. `both` requires an explicitly dual-platform request. iOS-only work must not package or install macOS.
8. Start product work from current `origin/main`; do not treat an unmerged PR or moving platform SHA as the default product baseline.
9. Local AppKit/UI fixes use the project route and real-window verification; do not invoke Product Design unless the user requests it or the task requires visual reproduction from a reference.

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

## Delivery

- Follow `/Users/Donald/Code/Devflow/README.md` and use `/Users/Donald/Code/Devflow/bin/devtask`.
- Devflow may call `./scripts/verify pr|full`; the dispatcher detects a single-platform diff and delegates only to that platform. Documentation-only changes run policy checks without building either app.
- `live` always requires an explicit platform argument or `MUDSNOTE_PLATFORM_SCOPE`; it never infers an installation target.
- Concurrent worktrees share `/Applications/Mudsnote.app` and the connected iPhone, so never run another platform's live flow as incidental verification.
- PR CI must not access iCloud, Keychain, real note folders, personal settings, credentials, or other user data.
- Reversible product tasks use Devflow v2 Ready PRs and event-driven merge by default. Importance changes the final report, not the approval path.
- Use `devtask ... --json` for stage results and `devtask wait` once; never poll CI from the model loop.
- If installation is required, use `devtask install ... --json`; it must verify the merged, clean `main`, never the task branch.
- For `--iteration-mode ui-tuning`, keep local adjustments in one task/branch and create one PR after the UI stabilizes. Official installation remains post-merge from `main`.
- Merge-candidate CI runs `full` once. Post-merge uses platform `pr` smoke unless the base/candidate changed, merge queue created a new candidate, or migration/signing/release/explicit high-risk review requires another full run.
- Irreversible data, production/App Store release, signing/secrets, guardrail weakening, and workflow/verification/package/entitlement changes remain held from automatic merge.
- Existing legacy PRs without a Devflow v2 manifest remain manual and must never be merged retroactively by the automation.
