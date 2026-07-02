# 2026-07-02 full Apple Notes parity goal

## Request

The user said the current completion level is still far from Apple Notes and asked to set the goal as a complete Notes function and UI clone.

## Baseline

- Branch: main
- HEAD: 30c0bcb
- Dirty files before work: none after checkpointing the previous Apple Notes-style library parity slice.

## Changes

- Added `docs/apple-notes-parity-roadmap.md` as the explicit goal and acceptance checklist.
- Added `agent-memory/decisions/2026-07-02-full-apple-notes-parity-target.md` to supersede the earlier loose Notes-like target.
- Kept the product boundary explicit: full core Apple Notes desktop parity, but local-first Markdown and no Apple/iCloud private-service dependency.

## Verification

- `git diff --check` passed.
- No app build was run because this iteration only created product goal and planning documents.

## Decisions

- Future work should be chosen from the parity roadmap.
- Each implementation slice should record which roadmap checklist item it closes.
- Visual QA should compare Mudsnote against the supplied Apple Notes screenshot state.

## Next

- P0 shell work:
  - convert top actions into a Notes-like toolbar
  - move search into the toolbar
  - move editor date/status toward centered Notes placement
  - add real source-list folder hierarchy and trash entry behavior
