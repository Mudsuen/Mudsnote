# Mudsnote Agent Memory Start Here

Read this before opening deeper Mudsnote memory.

## Fast Path

1. Read `AGENTS.md`.
2. For substantial app work, read the compact `docs/AI_HANDOFF.md` once.
3. List task routes with `./scripts/agent_context.sh --list` and select one.
4. Search only that route with `./scripts/agent_context.sh <topic> '<regex>'`.
5. Search `agent-memory/decisions` or `agent-memory/incidents` only when current
   code and handoff do not answer a decision or failure question.
6. Use iteration records, archives, or global `.codex` memory only as a final
   evidence fallback.

## Default Context Budget

The default entry set is only:

- `README.md`
- `AGENTS.md`
- this file
- `docs/AI_HANDOFF.md` for substantial work

`docs/ARCHITECTURE.md`, product roadmaps, `CHANGELOG.md`, refactor history, and
old iteration records are on-demand sources. Do not load them together by default.

## What Lives Where

- `docs/AI_HANDOFF.md`
  Compact current state and durable takeover constraints.
- `docs/ARCHITECTURE.md`
  Stable application boundaries and human-readable task routes.
- `scripts/agent_context.sh`
  Executable topic routing and narrow source/test search.
- `docs/REFACTOR_LOG.md`
  Refactor notes and iteration history.
- `agent-memory/PROJECT_MEMORY_INDEX.md`
  Migration index for Mudsnote / QuickMarkdown memory topics.
- `agent-memory/incidents/YYYY/`
  Concrete bugfix or packaging incidents.
- `agent-memory/decisions/`
  Durable app architecture or workflow decisions.
