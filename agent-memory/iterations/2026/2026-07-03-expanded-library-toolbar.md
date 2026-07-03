# 2026-07-03 expanded library toolbar

## Context

Continue the macOS Apple Notes parity goal. The latest side-by-side visual QA still showed Mudsnote's top toolbar feeling thinner and lighter than Apple Notes.

Baseline before this slice: `0e35ba4 Left align library editor titles`.

## Changes

- Switched the library window toolbar style from unified to expanded.
- Added a shared toolbar SF Symbol point-size metric.
- Applied the shared 20pt symbol configuration to toolbar buttons, menu toolbar items, and the grouped editor-tool buttons.
- Added regression coverage for the expanded toolbar style and symbol sizing metric.

## Validation

- `swift test --filter MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote`
- `swift test`
- `./scripts/package_app.sh`
- `/usr/bin/time -p ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-expanded-toolbar`

Packaged visual QA completed in 6.79s and captured:

- `mudsnote_window_bounds=x=36,y=69,width=1440,height=877`
- comparison image: `/tmp/mudsnote-visual-qa-expanded-toolbar/apple-notes-vs-mudsnote.png`

## Notes

- `NSToolbar.showsBaselineSeparator` is deprecated and ineffective on the current macOS runtime, so it was not used.
- The current screen's visible frame clamped the expanded-toolbar window to 1440px width during visual QA; the layout stayed nonblank and functional.
