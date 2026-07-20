# Token-efficient agent context

## Context

The mandatory repository entry path had grown to 802 lines, mostly
because `docs/AI_HANDOFF.md` repeated chronological iteration summaries already
represented by `CHANGELOG.md`, project iteration records, and Git history. Large
macOS and iOS source files also made broad searches and whole-file reads costly.

## Decision

- Keep `docs/AI_HANDOFF.md` as compact current state, not an iteration log.
- Keep stable application boundaries in `docs/ARCHITECTURE.md`.
- Route source and tests by topic through `scripts/agent_context.sh` before search.
- Enforce 220-line/1,400-word default entry budgets, focused handoff/architecture
  budgets, valid routed paths, and no chronological handoff sections during verification.
- Use symbol-first reads for existing hotspots. Add independent responsibilities
  in focused files and perform broad structural extraction only in dedicated,
  behavior-preserving tasks.
- Extract macOS source projections/layout and iOS path/models/search into focused
  files while retaining their existing tests and callers.

## Consequences

Normal tasks load less repeated context while preserving current constraints and
historical evidence on demand. At this checkpoint the entry set is 187 lines
(`-76.7%`) and 1,112 words instead of 6,903 (`-83.9%`). Architecture and workflow
drift now fail policy verification. The two largest platform stores/controllers
retain orchestration while pure, independently testable responsibilities have
focused owners.

## Rejected

- Keeping the complete iteration stream in the mandatory handoff.
- Default-reading every roadmap, changelog, refactor log, and memory index.
- Performing an unrequested cross-platform god-file split in the same workflow
  change, which would add significant regression risk without changing behavior.
