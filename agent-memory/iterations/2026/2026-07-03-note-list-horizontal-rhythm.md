# 2026-07-03 - Note-list Horizontal Rhythm

## Context

The Apple Notes comparison still showed the middle pane as an area that needs repeated spacing passes. The note-list header, empty state, row content, and list container used scattered inset values, which made tuning the Notes-like rhythm fragile.

## Change

- Added explicit `LibraryNotesLayout` constants for note-list top, leading, trailing, and bottom insets.
- Named the note-list stack as `LibraryNoteListStack` so tests can inspect the pane's spacing contract.
- Added explicit `LibraryNoteCellView` content inset constants and used them in the cell stack.
- Added regression coverage for the note-list stack insets and note-cell content insets.
- Kept this iteration macOS-only; iOS real-device validation is excluded from the current goal.

## Verification

- `swift test --filter libraryWindowUsesNotesLikeSplitAndLoadsFirstNote` passed.
- `swift test` passed with 81 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged-app smoke confirmed direct library launch exposes `Mudsnote 笔记` windows in the current macOS session.
- `./scripts/visual_notes_qa.sh` could not complete because the current macOS screen capture session returned a pure-black full-screen image (`nonBlack=0`) after window capture was unavailable. The Mudsnote library window itself was present on screen.
- `git diff --check` passed.
