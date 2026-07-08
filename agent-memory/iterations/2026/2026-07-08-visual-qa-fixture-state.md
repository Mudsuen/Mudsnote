# 2026-07-08 visual QA fixture state

## Request

Continue the Apple Notes parity goal with UI alignment first and performance treated as a first-class constraint.

## Baseline

- Branch: `main`
- HEAD before work: `a5cc8d0 Align Notes root folder label`
- Dirty files before work: none
- Visual issue: the side-by-side QA screenshot depended on the user's live notes, so the Mudsnote half often opened in a different date-group state than the Apple Notes reference.

## Changes

- Added a visual-QA-only launch path that creates `NoteStore` with an isolated UserDefaults suite, temporary notes directory, and temporary app-support directory.
- Updated `scripts/visual_notes_qa.sh` to seed a deterministic temporary library with Today, Previous 7 Days, Previous 30 Days, and year groups before opening the installed app.
- Kept the QA fixture local to the output directory so visual comparison no longer reads or writes the user's real note library.
- Fixed deferred library launch for external Markdown libraries with an empty recent list: when the full snapshot arrives, the first note is selected and loaded instead of leaving the editor empty.
- Added regression coverage for the isolated QA launch store and the external-plain-Markdown deferred-load path.

## Verification

- Commands run before final verification:
  - `swift test --filter 'MarkdownRichEditorTests/appControllerVisualQAModeUsesIsolatedNoteStore|MarkdownRichEditorTests/defaultLaunchOpensLibraryUnlessAnotherSurfaceIsRequested|MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|MarkdownRichEditorTests/librarySourceListDisplaysDefaultNotesFolderLikeAppleNotes'`
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-notes-fixture-state`
  - `swift test --filter 'MarkdownRichEditorTests/libraryWindowDeferredShowLoadsFirstPlainMarkdownWhenRecentsAreEmpty|MarkdownRichEditorTests/libraryWindowDeferredShowLoadsFirstNoteWithoutFocusingSearch|MarkdownRichEditorTests/appControllerVisualQAModeUsesIsolatedNoteStore|MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote'`
- App/package actually opened:
  - `/Applications/Mudsnote.app` via the visual QA harness.
- Final verification:
  - `swift test`
  - `git diff --check`
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-fixture-state-final`
- Result:
  - Full `swift test` passed with 94 tests.
  - `git diff --check` passed.
  - Final visual QA captured `/tmp/mudsnote-visual-qa-fixture-state-final/apple-notes-vs-mudsnote.png`.
  - The final screenshot uses the temporary fixture library and shows the Notes-like Today / Previous 7 Days / Previous 30 Days / year groups with the first note selected.
  - Installed app refreshed at `/Applications/Mudsnote.app`.

## Decisions

- Keep the visual QA path as a launch argument instead of changing default app behavior or user data.
- Treat stable visual comparison state as part of the parity workflow; if the comparison starts from different content/date groups, it hides the real UI deltas.

## Next

- Continue closing visible deltas now that screenshots are more comparable: source/sidebar scale, toolbar placement, selected-row geometry, and editor title/date spacing.
