# 2026-07-03 Background Library Indexing Status

## Request

Continue the active macOS Apple Notes parity goal for Mudsnote while keeping launch lightweight and local-first.

## Baseline

- Branch: `main`
- HEAD: `735067e`
- Dirty files before work: none

## Changes

- Added an `isFullLibrarySnapshotLoading` state to the library window.
- When direct launch defers full-library hydration, the note-list count temporarily shows `正在索引...`.
- The lightweight recent-backed shell still appears first and the full Markdown snapshot remains on a background queue.
- When the background snapshot is applied, the note-list count returns to the normal `N 条笔记` display.

## Verification

- Focused tests passed:
  - `swift test --filter 'libraryWindowDeferredShowLoadsFirstNoteWithoutFocusingSearch|libraryWindowDoesNotFocusSearchOnDefaultShow'`
- `swift test` passed.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged-app direct launch smoke opened `Mudsnote 笔记` at `1840x978`.
- Visual QA generated `/tmp/mudsnote-visual-qa-background-library-indexing-status/apple-notes-vs-mudsnote.png`.

## Decisions

- Keep full-library hydration asynchronous; the new state is progress feedback, not a heavier indexing architecture.

## Next

- Continue toolbar visual tuning.
- Consider cancellable/incremental refresh if large-library scans become noticeably slow.
