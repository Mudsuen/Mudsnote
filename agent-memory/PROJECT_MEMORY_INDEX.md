# Mudsnote Project Memory Index

This file records project-local ownership for Mudsnote and older QuickMarkdown memory topics that previously lived in global `.codex` memory or Automation memory.

The old sources are intentionally left searchable during migration.

## Primary Routes

| Topic | New project-local entrypoint | Legacy source retained |
| --- | --- | --- |
| Mudsnote app workflow | `AGENTS.md`; `docs/AI_HANDOFF.md` | `.codex/memories/memory.md` |
| QuickMarkdown history reuse / repo migration | `docs/AI_HANDOFF.md`; this index | `.codex/memories/memory.md` |
| Markdown clipboard / export / bullet rendering | `docs/AI_HANDOFF.md`; `agent-memory/incidents/2026/` for future notes | `.codex/memories/memory.md` |
| Packaged app validation | `AGENTS.md`; `scripts/package_app.sh` | `.codex/memories/memory.md`; Automation incidents |

## Search Keywords

- `Mudsnote`
- `QuickMarkdown`
- `MarkdownTextView`
- `copy(_)`
- `cut(_)`
- `serializeSelection`
- `bullet`
- `/Applications/Mudsnote.app`
- `package_app.sh`

## Migration Policy

This is an additive migration. Keep legacy sources until keyword regression tests prove that old queries route here reliably.
