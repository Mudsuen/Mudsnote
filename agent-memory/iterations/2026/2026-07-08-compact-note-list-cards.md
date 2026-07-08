# 2026-07-08 Compact note-list cards

## Request

Continue the active Mudsnote Apple Notes parity goal, with emphasis on the earlier, lighter UI direction and avoiding oversized controls or list chrome.

## Baseline

- Branch: `main`
- HEAD before work: `cb5a77e Tighten Notes source list rhythm`
- Dirty files before work: none
- Visual baseline: `/tmp/mudsnote-visual-qa-compact-source-list-final/apple-notes-vs-mudsnote.png` showed the toolbar and source list moving closer to the earlier compact Notes-like version, while the middle note-list card typography and row height still looked heavy against Apple Notes.

## Changes

- Kept the three-line Notes-like note-row structure:
  - title
  - time plus preview
  - folder/tags row
- Reduced note-list row weight without reverting to the older two-line list:
  - note row height from 118pt to 106pt
  - group row height from 60pt to 54pt
  - title/snippet/meta/group fonts each reduced one step
  - cell top/bottom padding from 15pt to 12pt
  - vertical text-row spacing from 4pt to 3pt
- Added regression expectations for the compact row metrics.
- Updated the Apple Notes parity roadmap to record the compact three-line note-list direction.

## Verification

- Commands run:
  - `swift test --filter 'MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|MarkdownRichEditorTests/libraryNoteListShowsImageAttachmentThumbnail|MarkdownRichEditorTests/libraryWindowShowsEmptyMarkdownFileAsBlankEditorNewNote|MarkdownRichEditorTests/libraryWindowNoteListArrowKeysSkipGroupRowsAndLoadNotes'`
  - `swift test`
  - `git diff --check`
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-compact-note-list-final`
- App/package actually opened:
  - `/Applications/Mudsnote.app` via the visual QA harness after packaging.
- Result:
  - Focused note-list layout, thumbnail, empty-note, and keyboard-browsing tests passed.
  - Full `swift test` passed with 98 tests.
  - `git diff --check` passed.
  - Packaged app refreshed at `/Applications/Mudsnote.app`.
  - Final visual QA captured `/tmp/mudsnote-visual-qa-compact-note-list-final/apple-notes-vs-mudsnote.png`.
  - Final metadata recorded `mudsnote_window_bounds=x=46,y=78,width=1420,height=860` and `frontmost_before_capture=Mudsnote`.
  - Visual inspection confirmed the note-list cards and group rows are lighter, with more Notes-like density while preserving the title/preview/folder row structure.
- Not verified:
  - iOS real-device validation remains intentionally out of scope for the current macOS Notes-parity goal.

## Decisions

- Do not return all the way to the old 92pt note rows because the current Apple Notes parity target needs a separate folder/tags metadata row.
- Keep the change visual-only and avoid extra note reads, indexing, or store changes.

## Next

- Run focused UI tests, full tests, package the app, and capture side-by-side visual QA.
