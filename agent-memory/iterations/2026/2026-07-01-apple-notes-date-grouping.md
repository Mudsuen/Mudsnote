# 2026-07-01 Apple Notes date grouping

## Request

Continue iterating Mudsnote's desktop interface and functionality with the explicit target of replicating Apple Notes.

## Baseline

- Branch: main
- HEAD: 2504e7f
- Dirty files before work: none after checkpointing the previous Notes-style library launch and iOS icon iteration.

## Changes

- Added the durable decision `agent-memory/decisions/2026-07-01-apple-notes-clone-target.md`.
- Changed the library note list from a flat table into Apple Notes-style date sections:
  - 今天
  - 昨天
  - 过去 7 天
  - 过去 30 天
  - older year labels
- Added non-selectable group rows and preserved automatic selection of the first real note.
- Left-aligned the note-list cards to match Apple Notes' readable middle column.
- Added a custom selected-row background so selected notes use a Notes-like golden card highlight.
- Kept search, tag filtering, double-click handoff, and note loading routed through real note rows only.
- Updated the library regression test to cover group rows and non-selectable headers.

## Verification

- `swift test` passed with 58 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged smoke launched `/Applications/Mudsnote.app` with no arguments and showed the `Mudsnote 笔记` library window directly.
- Visual QA screenshot: `/tmp/mudsnote-window-apple-notes-selection.png`
  - three-column library is visible
  - note list has a `2026` date group
  - note cards are left-aligned
  - selected note uses a golden Notes-like highlight

## Decisions

- The Apple Notes target starts with information architecture and interaction behavior before copying every toolbar icon.
- Group headings are localized to the current Chinese UI while matching Apple Notes' recency sections structurally.

## Next

- Continue parity work with source-list folder hierarchy.
- Move editor date/status placement closer to Apple Notes.
- Tighten toolbar density and note-list spacing against screenshot comparisons.
