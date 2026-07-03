# 2026-07-03 - Notes-like List Typography

## Context

After the library window proportions were enlarged, the visual QA side-by-side still showed Mudsnote's source list and note list reading smaller and lighter than Apple Notes. The layout was closer, but the information hierarchy still felt scaled down.

## Change

- Centralized list typography and row-height metrics in `LibraryNotesLayout`.
- Increased source-list row height and source button/count/group font sizes.
- Increased note-list group, title, snippet, and metadata font sizes.
- Added slightly more vertical padding to note rows to fit the stronger typography.
- Kept this iteration macOS-only; iOS real-device validation is excluded from the current goal.

## Verification

- `swift test --filter 'libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|libraryWindowSearchScopesAndHighlightsMatches|libraryNoteScrollViewFitsSingleColumnToVisibleWidth'` passed.
- `swift test` passed: 82 tests.
- `git diff --check` passed.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged-app smoke passed: `open -n /Applications/Mudsnote.app --args --library` produced one on-screen `Mudsnote 笔记` window at 1420x860.
- `./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-typography` passed and wrote `/tmp/mudsnote-visual-qa-typography/apple-notes-vs-mudsnote.png`.

## Remaining Visual Delta

- The source list and note list now read stronger, but side-by-side QA still shows toolbar scale/balance and editor top spacing as visible differences from Apple Notes.
