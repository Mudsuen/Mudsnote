# 2026-07-02 Notes visual QA harness

## Context

The Apple Notes parity roadmap required side-by-side comparison against the supplied reference screenshot. Previous iterations saved individual smoke screenshots, but there was no repeatable comparison artifact.

## Change

- Saved the supplied Apple Notes screenshot as `docs/visual-qa/apple-notes-reference.png`.
- Added `scripts/visual_notes_qa.sh`.
  - Launches `/Applications/Mudsnote.app`.
  - Finds the visible Mudsnote library window.
  - Captures that window.
  - Stitches the Apple Notes reference and Mudsnote current screenshot into `/tmp/mudsnote-visual-qa/apple-notes-vs-mudsnote.png`.
- Changed default library `showWindowAndFocus()` behavior so direct-open does not focus the toolbar search field.
- Added regression coverage for the direct-show focus contract.

## Verification

- `swift test --filter 'libraryWindowDoesNotFocusSearchOnDefaultShow|defaultLaunchOpensLibraryUnlessAnotherSurfaceIsRequested'` passed.
- `swift test --filter 'libraryWindowDeferredShowLoadsFirstNoteWithoutFocusingSearch|libraryWindowDoesNotFocusSearchOnDefaultShow|libraryWindowUsesNotesLikeSplitAndLoadsFirstNote'` passed.
- `swift test` passed with 77 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- `./scripts/visual_notes_qa.sh` generated `/tmp/mudsnote-visual-qa/apple-notes-vs-mudsnote.png`.
- The generated comparison confirmed the installed app direct-open path loads the first note and does not focus the search field by default.

## Follow-Up

- Use the side-by-side artifact before future visual tuning.
- Current visible deltas include toolbar balance, source-list width/density, editor title scale, and overall window proportion/content state.
