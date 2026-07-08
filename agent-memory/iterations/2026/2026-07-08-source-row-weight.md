# 2026-07-08 Source row weight

## Request

Continue the active Mudsnote Apple Notes parity goal, focusing on UI alignment first while keeping performance lightweight.

## Baseline

- Branch: `main`
- HEAD before work: `730a47c Add Notes call recordings source`
- Dirty files before work: none
- Visual baseline: `/tmp/mudsnote-visual-qa-next-iteration-baseline/apple-notes-vs-mudsnote.png`
- The source-list structure now includes `Call Recordings 2` above the `iCloud` header, but unselected source rows still read too dim compared with Apple Notes. Apple Notes keeps source row text/icons closer to primary text strength while leaving counts and section labels subdued.

## Changes

- Added `LibrarySourceSelectionPalette.unselectedForegroundColor`.
- Applied that brighter unselected foreground to source-row button text/icons at creation and during selection refresh.
- Kept selected rows, counts, section headers, hover, row height, and layout unchanged.
- Added regression coverage for the unselected `Call Recordings` row tint.
- Updated the Apple Notes parity roadmap.

## Verification

- Focused tests passed:
  `swift test --filter 'MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|MarkdownRichEditorTests/libraryCallRecordingsSourceFiltersExistingSnapshot|MarkdownRichEditorTests/librarySourceListDisplaysDefaultNotesFolderLikeAppleNotes|MarkdownRichEditorTests/librarySourceListShowsZeroCountsForEmptyFoldersLikeAppleNotes'`
- Full tests passed:
  `swift test` (`100` tests in `2` suites).
- Whitespace check passed:
  `git diff --check`
- Packaged app successfully:
  `./scripts/package_app.sh`
  - app path: `/Applications/Mudsnote.app`
- Content visual QA passed:
  `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=content ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-source-row-weight-final`
  - comparison: `/tmp/mudsnote-visual-qa-source-row-weight-final/apple-notes-vs-mudsnote.png`
  - metadata: `/tmp/mudsnote-visual-qa-source-row-weight-final/visual-qa-metadata.txt`
  - selected note: `/tmp/mudsnote-visual-qa-source-row-weight-final/visual-qa-library/Notes/lz合集.md`
  - visual inspection confirmed unselected source row text/icons read closer to Apple Notes while counts and section labels remain subdued.

## Decisions

- Keep this as a constant-level visual correction. It does not add custom drawing, file reads, indexing, or source-list rebuild work.
- Counts remain tertiary unless selected; the brightness change applies only to source row text/icons.

## Next

- Continue with editor horizontal positioning and note-list sample-state parity from the final QA output.
