# 2026-07-03 Larger Editor Typography

## Request

Continue the active macOS Apple Notes parity iteration for Mudsnote while preserving the lightweight quick-capture boundary.

## Baseline

- Branch: `main`
- HEAD: `6a35d93`
- Dirty files before work: none

## Changes

- Added explicit `LibraryNotesLayout` typography metrics for the library editor:
  - status/date font
  - title font
  - body font
  - code font
- Increased the Notes-like library editor title, body, bold, italic, and code sizes.
- Left the quick-capture/editor-window theme unchanged so fast capture stays compact.
- Added regression coverage for the library editor typography contract.

## Verification

- Focused editor tests passed:
  - `swift test --filter 'libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|libraryWindowEditorToolbarInsertsRichMarkdownTools|libraryWindowAutosavesEditedExistingNote'`
- `swift test` passed.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged-app direct launch smoke opened `Mudsnote 笔记` at `1840x978`.
- Visual QA generated `/tmp/mudsnote-visual-qa-larger-editor-typography/apple-notes-vs-mudsnote.png`.

## Decisions

- The Notes-like library editor owns separate typography metrics from quick capture.

## Next

- Continue source-list hierarchy and toolbar visual tuning.
- Add richer drag preview/count visuals.
