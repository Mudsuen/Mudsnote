# 2026-07-03 - True All-notes Scope

## Context

The library was visually moving toward Apple Notes, but `所有笔记` still depended on recent-file state. That made the local-first promise weaker: a Markdown file copied into the notes folder through Finder could exist on disk without appearing in the Notes-like All view.

## Change

- Switched the `所有笔记` scope to use full-library indexed note results.
- Switched Inbox matching and source-list counts to derive from full-library note results.
- Kept `最近` backed by recent files so it remains a distinct recent-access scope.
- Added regression coverage for a Finder-created Markdown file that appears in `所有笔记` and the all-count, while `最近` remains empty.
- Kept this iteration macOS-only; iOS real-device validation is excluded from the current goal.

## Verification

- `swift test --filter libraryAllNotesIncludesPlainMarkdownOutsideRecents` passed.
- `swift test` passed with 82 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- `./scripts/visual_notes_qa.sh` passed and generated `/tmp/mudsnote-visual-qa/apple-notes-vs-mudsnote.png`.
- Visual QA confirmed the packaged library window opens and renders nonblank after the scope-count change.
- `git diff --check` passed.
