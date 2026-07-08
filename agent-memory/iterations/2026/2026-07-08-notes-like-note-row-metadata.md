# 2026-07-08 Notes-like note row metadata

## Request

Continue the active Mudsnote Apple Notes parity goal, prioritizing UI alignment while keeping the app lightweight and performant.

## Baseline

- Branch: `main`
- HEAD before work: `8f893ac Restore compact Notes shell geometry`
- Dirty files before work: none
- Visual baseline: `/tmp/mudsnote-visual-qa-active-compact-shell-final/apple-notes-vs-mudsnote.png` showed the compact window and toolbar in a better place, but note-list rows still differed from Apple Notes: Mudsnote collapsed date, folder, and tags into one metadata line, and empty notes had no visible "No additional text" preview.

## Changes

- Changed library note-list rows to a more Apple Notes-like three-line structure:
  - title
  - time plus preview text
  - folder/tags line
- Added a small folder icon to the folder/tags row.
- Empty Markdown notes now show `No additional text` in the note-list preview while keeping the editor title/body blank.
- Kept this as a presentation-only change using existing `NoteSearchResult` fields, with no extra file reads or indexing work.
- Updated drag preview fallback text to use the same note-list preview helper.
- Updated regression tests and the parity roadmap.

## Verification

- Commands run:
  - `swift test --filter 'MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|MarkdownRichEditorTests/libraryWindowShowsEmptyMarkdownFileAsBlankEditorNewNote|MarkdownRichEditorTests/librarySourceListDisplaysDefaultNotesFolderLikeAppleNotes|MarkdownRichEditorTests/libraryWindowSearchScopesAndHighlightsMatches|MarkdownRichEditorTests/libraryNoteListShowsImageAttachmentThumbnail'`
  - `swift test`
  - `git diff --check`
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-note-row-metadata-final`
- App/package actually opened:
  - `/Applications/Mudsnote.app` via the final visual QA harness after packaging.
- Result:
  - Focused note-list layout, empty-note, default-folder, search-highlight, and thumbnail tests passed.
  - Full `swift test` passed with 98 tests.
  - `git diff --check` passed.
  - Packaged app refreshed at `/Applications/Mudsnote.app`.
  - Final visual QA captured `/tmp/mudsnote-visual-qa-note-row-metadata-final/apple-notes-vs-mudsnote.png`.
  - Final metadata recorded `mudsnote_window_bounds=x=46,y=78,width=1420,height=860` and `frontmost_before_capture=Mudsnote`.
  - Visual inspection confirmed the selected note card now shows title, time-plus-`No additional text`, and a separate folder row.
- Not verified:
  - iOS real-device validation remains intentionally out of scope for the current macOS Notes-parity goal.

## Decisions

- Keep note-list row rendering driven by already-loaded search/list metadata; do not add synchronous file reads for visual parity.
- Use `No additional text` as the local Apple Notes-like empty-preview copy for blank Markdown files.

## Next

- Continue visual tuning on source-list hierarchy rhythm, note-row spacing, and editor date/title positioning.
