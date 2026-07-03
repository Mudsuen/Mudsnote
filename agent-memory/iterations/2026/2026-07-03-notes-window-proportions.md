# 2026-07-03 - Notes-like Library Window Proportions

## Context

The visual QA side-by-side showed that the library window still opened at a utility-app scale. Even with correct three-column structure, the source list, note list, editor area, and toolbar search field looked compressed compared with Apple Notes.

## Change

- Increased the default library window size from 1160x764 presentation to a larger 1420x860 Notes-like desktop editor scale.
- Widened the source column, note column, source rows, note table, and toolbar search field to match the larger first-viewport proportions.
- Added screen-visible-frame clamping so the larger default window remains usable on smaller displays.
- Kept this iteration macOS-only; iOS real-device validation is excluded from the current goal.

## Verification

- `swift test --filter 'libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|libraryNoteScrollViewFitsSingleColumnToVisibleWidth'` passed.
- `swift test` passed: 82 tests.
- `git diff --check` passed.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged-app smoke passed: `open -n /Applications/Mudsnote.app --args --library` produced an on-screen `Mudsnote 笔记` window at 1420x860.
- `./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-proportions` passed and wrote `/tmp/mudsnote-visual-qa-proportions/apple-notes-vs-mudsnote.png`.

## Remaining Visual Delta

- The larger window improves desktop-editor proportions, but the visual QA still shows source-list and note-list typography reading smaller/lighter than the Apple Notes reference. Treat that as the next focused visual tuning pass.
