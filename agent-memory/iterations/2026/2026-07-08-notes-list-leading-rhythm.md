# 2026-07-08 Notes list leading rhythm

## Request

Continue the active Mudsnote Apple Notes parity goal, focusing first on UI alignment while keeping the app lightweight and performant.

## Baseline

- Branch: `main`
- HEAD before work: `86ce4c7 Tighten Notes toolbar scale`
- Dirty files before work: none
- Visual baseline: `/tmp/mudsnote-visual-qa-compact-toolbar-baseline-final/apple-notes-vs-mudsnote.png`

## Changes

- Increased note-list cell leading inset so note titles and snippets no longer sit almost flush against the selected golden card edge.
- Shifted note-list group headers right to match the same visual rhythm.
- Shifted normal-row separators right so dividers stay aligned with the denser Notes-like content column.
- Added regression assertions for the group header inset, note cell leading inset, and separator alignment.

## Verification

- Commands run:
  - `swift test --filter 'MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|MarkdownRichEditorTests/libraryNoteScrollViewFitsSingleColumnToVisibleWidth|MarkdownRichEditorTests/libraryWindowNoteListKeyboardOpensAndDeletesNotes|MarkdownRichEditorTests/libraryWindowNoteListArrowKeysSkipGroupRowsAndLoadNotes'`
  - `swift test`
  - `git diff --check`
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-note-list-leading-rhythm-final`
- App/package actually opened:
  - `/Applications/Mudsnote.app` via the visual QA harness.
- Result:
  - Focused note-list tests passed.
  - Full `swift test` passed with 95 tests.
  - `git diff --check` passed.
  - Packaged app refreshed at `/Applications/Mudsnote.app`.
  - Visual QA captured `/tmp/mudsnote-visual-qa-note-list-leading-rhythm-final/apple-notes-vs-mudsnote.png`.
- Not verified:
  - iOS real-device validation remains intentionally out of scope for the current macOS Notes-parity goal.

## Decisions

- Keep this as a constant-level visual correction. It improves the Notes-like middle pane without adding rendering work, custom drawing layers, or data-model complexity.

## Next

- Continue with editor date/title empty-state parity and source-sidebar spacing once the note-list rhythm is verified.
