# 2026-07-03 List Scale And Visual QA Metadata

## Request

Continue the active macOS Apple Notes parity goal for Mudsnote while keeping the app lightweight and local-first.

## Baseline

- Branch: `main`
- HEAD: `fe6de9b`
- Dirty files before work: none

## Changes

- Added point size, pixel size, backing-scale, and draw-scale metadata to `scripts/visual_notes_qa.sh`.
- The side-by-side visual QA image now labels the Apple Notes reference and Mudsnote current screenshot with their logical and bitmap dimensions.
- The visual QA run writes `visual-qa-metadata.txt` beside the screenshots so future UI passes can distinguish real layout gaps from 1x/2x capture differences.
- Increased the Notes-like source-list hierarchy scale:
  - source rows: `34 -> 40`
  - source group labels: `13.5 -> 14.5`
  - source buttons: `15.5 -> 16.5`
  - source counts: `14 -> 15`
- Increased the note-list hierarchy scale:
  - group rows: `62 -> 66`
  - note rows: `86 -> 92`
  - note titles: `16.5 -> 17.5`
  - snippets: `14.5 -> 15.5`
  - metadata: `12.5 -> 13`
  - header title/count: `21/13 -> 23/14`

## Verification

- `bash -n scripts/visual_notes_qa.sh` passed.
- Focused tests passed:
  - `swift test --filter MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote`
  - `swift test --filter MarkdownRichEditorTests/libraryWindowShowsNestedFoldersInSourceList`
  - `swift test --filter MarkdownRichEditorTests/libraryWindowEditorToolbarInsertsRichMarkdownTools`
- `swift test` passed with 86 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- `./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-list-scale-polish` passed.
- Visual QA metadata confirmed:
  - reference: `1862x1246 pt`, `1862x1246 px`, `1.0x`
  - Mudsnote: `1952x1090 pt`, `3904x2180 px`, `2.0x`
- Packaged-app smoke confirmed an on-screen `Mudsnote 笔记` window at `1840x978`.

## Decisions

- Treat visual QA comparisons as point-normalized evidence and keep pixel/backing-scale metadata next to every comparison.
- Keep the list scale increase conservative so the app remains lightweight and dense enough for repeated note work.

## Next

- Continue source-list hierarchy polish: section spacing, row grouping, and top-account affordances.
- Continue editor visual tuning against the updated point-normalized comparison.
