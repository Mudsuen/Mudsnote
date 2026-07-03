# 2026-07-03 - Single Library Snapshot Per Refresh

## Context

After `所有笔记` switched to true filesystem-backed results, the library refresh path could ask the Markdown index for the full library once for the visible list and again for source counts. That preserved correctness, but it was unnecessary work during ordinary Notes-like browsing.

## Change

- Built one full-library note snapshot at the start of `reloadNotes`.
- Reused that snapshot for `所有笔记`, Inbox, folder, tag, and source-list count filtering.
- Kept direct app launch responsive by drawing the library shell from a lightweight recent-note snapshot before the full-library snapshot finishes in the background.
- Kept `最近` backed by recent files so it remains semantically distinct.
- Expanded tag regression coverage so a tagged note beyond the first visible 240-note page is still found.
- Kept this iteration macOS-only; iOS real-device validation is excluded from the current goal.

## Verification

- `swift test --filter 'libraryWindowDoesNotFocusSearchOnDefaultShow|libraryWindowDeferredShowLoadsFirstNoteWithoutFocusingSearch|libraryWindowLoadsTagRowsAfterShellIsVisible|libraryAllNotesIncludesPlainMarkdownOutsideRecents'` passed.
- `swift test` passed: 82 tests.
- `git diff --check` passed.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged-app smoke passed: `open -n /Applications/Mudsnote.app --args --library` produced an on-screen `Mudsnote 笔记` window within 2 seconds.
- `./scripts/visual_notes_qa.sh` passed and wrote `/tmp/mudsnote-visual-qa/apple-notes-vs-mudsnote.png`.
