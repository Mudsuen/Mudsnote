# 2026-07-03 - Multi-Note Drag To Folder

## Context

Continue the active macOS Apple Notes parity goal with iOS real-device validation out of scope. The library already supported multi-note menu actions and single-note drag-to-folder moves, but folder drop targets only processed the first dragged Markdown file.

## Changes

- Updated source-list folder drop handling to read all dragged file URLs.
- Added batch drag validation through `canMoveDraggedNotesForLibrary(at:to:)`.
- Added batch drag move handling through `moveDraggedNotesForLibrary(at:to:)`.
- Kept the single-note drag API as a compatibility wrapper.
- Extended regression coverage so two project notes can be dragged to Archive together and the original paths are rejected after the batch move.

## Verification

- `swift test --filter 'libraryWindowCreatesMovesRenamesAndDeletesFolders|libraryWindowSharesExportsAndDeletesMultipleSelectedNotes|libraryToolbarUsesNotesLikeDisabledStates'` passed.
- `swift test` passed with 83 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged app smoke passed: `/Applications/Mudsnote.app --args --library` opened one `Mudsnote 笔记` window at `1420x860`.
- `./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-multi-drag-folder` passed and generated the side-by-side comparison image.

## Notes

- The implementation keeps the local-first file contract: dragged notes are still real Markdown file URLs, not app-private drag objects.
