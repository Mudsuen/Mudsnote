# 2026-07-03 - Cached Drag-move Validation

## Context

Drag-to-folder made the library feel closer to Apple Notes, but every drag-hover validation still called `noteStore.listNotes(limit: 10_000)` to prove the dragged Markdown file belonged to the current library. On larger local-first libraries, repeated hover validation should not repeatedly rebuild that path set.

## Change

- Added a cached movable-note path set inside `LibraryWindowController`.
- Switched drag-hover validation to set membership after the first library scan.
- Invalidated the cache after saves, note moves, delete/restore operations, folder creation/rename/delete, and dragged-note moves.
- Added regression coverage that warms the cache, moves a note, and verifies the new path is immediately recognized as movable.
- Kept this iteration macOS-only; iOS real-device validation is excluded from the current goal.

## Verification

- `swift test --filter libraryWindowCreatesMovesRenamesAndDeletesFolders` passed.
- `swift test` passed with 81 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged-app smoke confirmed direct library launch exposes a `Mudsnote 笔记` window.
- Visual QA was skipped after a screen-capture probe returned a pure-black image (`nonBlack=0`) in the current macOS session; the regression test covers this iteration's drag-validation behavior.
- `git diff --check` passed.
