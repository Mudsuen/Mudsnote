# 2026-07-03 - Selection-Count Action Wording

## Context

Continue the active macOS Apple Notes parity goal with iOS real-device validation out of scope. The previous iteration added multi-note file actions, but the menus still read like single-note actions and moving notes only operated on the loaded note.

## Changes

- Added selection-count-aware labels for share, copy path, copy content, export, Finder reveal, move, delete, restore, and permanent delete actions.
- Disabled `独立窗口打开` when more than one note is selected because it remains a single-note editor handoff.
- Extended `移到文件夹` to move all selected Markdown notes.
- Updated regression coverage for multi-selection menu titles and multi-note move behavior.

## Verification

- `swift test --filter 'libraryWindowSharesExportsAndDeletesMultipleSelectedNotes|libraryToolbarUsesNotesLikeDisabledStates|libraryWindowDeletesRestoresAndPermanentlyDeletesNotes'` passed.
- `swift test` passed with 83 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged app smoke passed: `/Applications/Mudsnote.app --args --library` opened one `Mudsnote 笔记` window at `1420x860`.
- `./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-selection-count-actions-final` passed and generated the side-by-side comparison image.

## Notes

- The implementation still treats notes as local Markdown files and does not introduce a metadata database.
