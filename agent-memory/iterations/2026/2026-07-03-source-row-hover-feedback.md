# 2026-07-03 source row hover feedback

## Context

Continue the active macOS Apple Notes parity goal. After aligning toolbar separators with the three-pane split view, the remaining visible shell gap was source-list polish. The source list already had selection tint and drag/drop highlighting, but ordinary pointer hover had no row-level response, making the left pane feel less native than Apple Notes.

Baseline before this slice: `8a844c1 Align toolbar separators with Notes panes`.

## Changes

- Added lightweight row-level pointer hover tracking to `LibrarySourceRowView`.
- Drew a quiet rounded hover fill behind source rows while preserving the stronger drag/drop target highlight.
- Added regression coverage for hover constants, hover state mutation, and drag-target priority on a source row.
- Updated the Apple Notes parity roadmap source-list status.

## Validation

- `swift test --filter MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote`
- `swift test`
- `./scripts/package_app.sh`
- `/usr/bin/time -p ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-source-row-hover-feedback`

Packaged visual QA completed in 6.75s and captured:

- `mudsnote_window_bounds=x=36,y=69,width=1440,height=877`
- comparison image: `/tmp/mudsnote-visual-qa-source-row-hover-feedback/apple-notes-vs-mudsnote.png`

## Notes

- This is intentionally visual/interaction polish only; it does not change source scopes, filesystem mapping, or local-first labels.
- The static visual QA does not show pointer hover, so unit coverage verifies the hover state path while visual QA verifies the packaged shell still renders correctly.
