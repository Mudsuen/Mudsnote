# 2026-07-03 Notes column density

## Context

Continue the macOS Apple Notes parity goal after removing iOS real-device validation from scope. The visual QA comparison showed Mudsnote already opens the three-column library by default, but the source/list columns and toolbar controls still read narrower and lighter than the Apple Notes reference.

Baseline before this slice: `e229844 Detach library search reloads`.

## Changes

- Widened the source column, note-list column, source rows, and table column so the main window reads closer to Apple Notes' heavier three-column layout.
- Widened the toolbar search field and editor tool capsule to reduce the compact utility-toolbar feel.
- Slightly increased toolbar symbol size and note-list horizontal insets for better parity with the supplied Notes screenshot.

## Validation

- `swift test --filter MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote`
- `swift test`
- `./scripts/package_app.sh`
- `/usr/bin/time -p ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-notes-column-density`

Packaged visual QA completed in 6.86s and captured:

- `mudsnote_window_bounds=x=36,y=69,width=1440,height=877`
- comparison image: `/tmp/mudsnote-visual-qa-notes-column-density/apple-notes-vs-mudsnote.png`

## Remaining visual gaps

- Toolbar item grouping still does not line up with Apple Notes' source/list/editor column anchors.
- Source list hierarchy still uses Mudsnote-specific library rows instead of the richer Apple Notes iCloud/call-recording grouping.
