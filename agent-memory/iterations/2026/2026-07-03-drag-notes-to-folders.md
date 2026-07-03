# 2026-07-03 - Drag Notes to Folders

## Context

The library already supported moving notes through toolbar/menu actions and dragging note rows out as real Markdown files. The missing Notes-like interaction was dropping a note row onto a folder in the source list to move it.

## Change

- Added `LibrarySourceRowView` as a lightweight folder drop target.
- Folder rows now accept dragged Markdown note URLs only when the note belongs to the current library, is not in trash, and is moving to a different folder.
- Dragging over a valid folder row shows a subtle drop highlight.
- Drops reuse `NoteStore.moveNote` through `moveDraggedNoteForLibrary(at:to:)`, preserving the local-first filesystem model and recent-file metadata updates.
- Added regression coverage for valid drag moves, same-folder rejection, source-row drop state, and folder target wiring.

## Verification

- `swift test` passed with 81 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- `./scripts/visual_notes_qa.sh` passed and generated `/tmp/mudsnote-visual-qa/apple-notes-vs-mudsnote.png`.
- `git diff --check` passed.
- iOS real-device validation is explicitly excluded from this goal.
