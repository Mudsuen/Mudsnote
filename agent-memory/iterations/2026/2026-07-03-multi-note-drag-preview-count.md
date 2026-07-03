# 2026-07-03 Multi-note Drag Preview Count

## Request

Continue the active macOS Apple Notes parity goal for Mudsnote. iOS real-device validation remains out of scope for this goal.

## Baseline

- Branch: `main`
- HEAD: `94e9d8e`
- Dirty files before work: none

## Changes

- Added a custom note-list drag preview image for Markdown note drags.
- Multi-note drags now use a piled card preview with a numeric count badge.
- Single-note drags keep a simple card preview without a count badge.
- Added a drag-session hook to use piled formation for multi-note drags.
- Kept drag payloads as real Markdown file URLs.

## Verification

- Focused tests passed:
  - `swift test --filter 'libraryWindowSharesExportsAndDeletesMultipleSelectedNotes|libraryWindowUsesNotesLikeSplitAndLoadsFirstNote'`
- `swift test` passed.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged-app direct launch smoke opened `Mudsnote 笔记` at `1840x978`.
- Visual QA generated `/tmp/mudsnote-visual-qa-multi-note-drag-preview-count/apple-notes-vs-mudsnote.png`.

## Decisions

- Drag previews are UI-only; the file URL drag payload remains the source of truth.

## Next

- Continue toolbar visual tuning against Apple Notes.
- Improve large-library search/loading state.
