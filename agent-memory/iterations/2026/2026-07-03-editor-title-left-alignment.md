# 2026-07-03 editor title left alignment

## Context

Continue the macOS Apple Notes parity goal after the initial-note loading shell pass. The side-by-side visual QA showed the selected note title sitting too far to the right in Mudsnote, unlike Apple Notes' left-starting editor title.

Baseline before this slice: `72b6b7c Show initial note loading shell`.

## Changes

- Set the library editor title field to explicit left alignment.
- Set title truncation to tail truncation so long note titles stay stable inside the editor header.
- Added regression coverage to the Notes-like split-window test for title alignment and truncation.

## Validation

- `swift test --filter MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote`
- `swift test`
- `./scripts/package_app.sh`
- `/usr/bin/time -p ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-editor-title-left-align`

Packaged visual QA completed in 6.65s and captured:

- `mudsnote_window_bounds=x=360,y=66,width=1840,height=978`
- comparison image: `/tmp/mudsnote-visual-qa-editor-title-left-align/apple-notes-vs-mudsnote.png`

## Notes

- This is intentionally a narrow visual correction. The editor still needs deeper side-by-side tuning for toolbar scale, canvas rhythm, and body content density.
