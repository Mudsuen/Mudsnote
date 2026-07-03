# 2026-07-03 toolbar tracking separators

## Context

Continue the active macOS Apple Notes parity goal. After widening the main columns, the side-by-side visual QA still showed a toolbar that was visually detached from the three-pane shell. Apple Notes uses toolbar separators aligned to pane boundaries, so Mudsnote needed native split-view tracking rather than more fixed spacing.

Baseline before this slice: `2c1112f Tune Notes library column density`.

## Changes

- Stored the library `NSSplitView` so the toolbar can bind to real pane dividers.
- Added `NSTrackingSeparatorToolbarItem` entries for the source-list and note-list boundaries.
- Moved toolbar configuration after UI construction so the tracking separators can bind to the actual split view.
- Added regression coverage for the two separator item identifiers, their split-view binding, and divider indices.

## Validation

- `swift test --filter MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote`
- `swift test`
- `./scripts/package_app.sh`
- `/usr/bin/time -p ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-toolbar-tracking-separators`

Packaged visual QA completed in 6.81s and captured:

- `mudsnote_window_bounds=x=36,y=69,width=1440,height=877`
- comparison image: `/tmp/mudsnote-visual-qa-toolbar-tracking-separators/apple-notes-vs-mudsnote.png`

## Notes

- This preserves the existing local-first source list labels; it improves Notes-like chrome without claiming iCloud or Apple account behavior.
- Remaining side-by-side gaps are source-list information hierarchy and toolbar icon-state detail, not the presence of pane-aligned toolbar separators.
