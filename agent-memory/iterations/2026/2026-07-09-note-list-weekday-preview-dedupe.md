# 2026-07-09 note list weekday preview dedupe

## Request

Continue the active Apple Notes parity goal, prioritizing UI alignment while preserving lightweight performance.

## Baseline

- Branch: `main`
- HEAD before work: `b482c75 Tighten Notes note-list row density`
- Dirty files before work: none
- Prior visual QA: `/tmp/mudsnote-visual-qa-note-list-row-density-final/apple-notes-vs-mudsnote.png`

## Changes

- Updated note-list snippet composition so date-plus-preview rows do not duplicate the same weekday prefix.
- Added a small preview cleanup helper that removes the date text only when it exactly matches or prefixes the preview.
- Preserved the normal `date + preview` behavior for ordinary notes and the `No additional text` empty-note preview.
- Added regression coverage for a note whose body starts with the same weekday displayed by the modified date.
- Updated the Apple Notes parity roadmap with the de-duplicated date-preview state.

## Verification

- Passed: `swift test --filter MarkdownRichEditorTests/libraryNoteListAvoidsDuplicatingWeekdayPrefixInSnippet`
- Passed: `swift test --filter 'MarkdownRichEditorTests/libraryNoteListAvoidsDuplicatingWeekdayPrefixInSnippet|MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote'`
- Passed: `swift test`
- Passed: `git diff --check`
- Passed: `./scripts/package_app.sh`
- Passed: `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=content ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-note-list-weekday-preview-dedupe-final`
- Visual QA metadata confirmed `frontmost_before_capture=Mudsnote` and `mudsnote_window_bounds=x=46,y=78,width=1420,height=860`.
- Visual inspection confirmed the selected `lz合集` row now shows `Monday 动机` instead of `Monday Monday 动机`.

## Decisions

- Keep this as presentation-layer cleanup only; do not alter stored Markdown, note metadata, search indexing, or snippet extraction in `NoteStore`.
- Return a single date text when the preview is exactly the same as the displayed date, avoiding `Monday Monday`-style rows.

## Next

- Revisit toolbar icon placement or selected-row color after the next side-by-side visual QA.
