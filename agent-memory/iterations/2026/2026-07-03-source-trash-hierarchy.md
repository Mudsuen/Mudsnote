# 2026-07-03 source trash hierarchy

## Context

Continue the active macOS Apple Notes parity goal. The source list still grouped `最近删除` with the top quick scopes (`所有笔记`, `最近`, `Inbox`). In Apple Notes, recently deleted is visually part of the account/folder hierarchy below ordinary folders, so this made the left pane feel less like Notes even though behavior was correct.

Baseline before this slice: `ef87d8a Dim disabled editor toolbar group`.

## Changes

- Added a dedicated source-list trash stack between folder rows and tag rows.
- Moved the `最近删除` row out of the primary quick-scope stack while keeping its stable `tag == 3`, count label id, click behavior, and trash workflow.
- Added stack identifiers for source-list primary/folder/trash/tag sections so tests can assert the visible hierarchy.
- Updated the Apple Notes parity roadmap source-list status.

## Validation

- `swift test --filter MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote`
- `swift test`
- `./scripts/package_app.sh`
- `/usr/bin/time -p ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-source-trash-hierarchy`

Packaged visual QA completed in 6.46s and captured:

- `mudsnote_window_bounds=x=36,y=69,width=1440,height=877`
- comparison image: `/tmp/mudsnote-visual-qa-source-trash-hierarchy/apple-notes-vs-mudsnote.png`

## Notes

- This is an information-architecture and visual hierarchy change only; it does not add iCloud behavior or Apple service labels.
- Keeping the trash row at source tag `3` preserved existing count labels and trash workflow tests.
