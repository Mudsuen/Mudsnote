# 2026-07-08 Call Recordings source

## Request

Continue the active Mudsnote Apple Notes parity goal, prioritizing UI alignment while keeping the app lightweight and performant.

## Baseline

- Branch: `main`
- HEAD before work: `daf9d74 Tune Notes editor body rhythm`
- Dirty files before work: none
- Visual baseline: `/tmp/mudsnote-visual-qa-next-baseline/apple-notes-vs-mudsnote.png`
- The toolbar already matched the earlier compact borderless direction. The visible source-list gap was that Apple Notes shows a top `Call Recordings` smart source, while Mudsnote started directly at the `iCloud` group.

## Changes

- Added a local `Call Recordings` smart source above `All iCloud`.
- Kept the source lightweight by filtering the existing in-memory `NoteSearchResult` snapshot instead of adding startup file reads or a new metadata model.
- Recognizes call-recording notes from existing title, snippet, or filename text such as `Call Recording`, `audio recording`, or `录音`.
- Added count, selection, list-title, empty-state, search-filter, and note-list filtering support for the new scope.
- Placed the smart source above the `iCloud` section header to match the supplied Apple Notes reference structure.
- Added a second call-recording note to the visual QA fixture so the source count matches the supplied Apple Notes screenshot's `2` count more closely.
- Added regression coverage for the source row, count, selection, and filtered result list.
- Updated the Apple Notes parity roadmap.

## Verification

- Focused tests passed:
  `swift test --filter 'MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|MarkdownRichEditorTests/libraryCallRecordingsSourceFiltersExistingSnapshot|MarkdownRichEditorTests/libraryAllNotesIncludesPlainMarkdownOutsideRecents|MarkdownRichEditorTests/libraryWindowSearchScopesAndHighlightsMatches'`
- Final focused tests passed:
  `swift test --filter 'MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|MarkdownRichEditorTests/libraryCallRecordingsSourceFiltersExistingSnapshot|MarkdownRichEditorTests/libraryAllNotesIncludesPlainMarkdownOutsideRecents|MarkdownRichEditorTests/librarySourceListDisplaysDefaultNotesFolderLikeAppleNotes'`
- Full tests passed:
  `swift test` (`100` tests in `2` suites).
- Whitespace check passed:
  `git diff --check`
- Packaged app successfully:
  `./scripts/package_app.sh`
  - app path: `/Applications/Mudsnote.app`
- Content visual QA passed:
  `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=content ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-call-recordings-final2`
  - comparison: `/tmp/mudsnote-visual-qa-call-recordings-final2/apple-notes-vs-mudsnote.png`
  - metadata: `/tmp/mudsnote-visual-qa-call-recordings-final2/visual-qa-metadata.txt`
  - selected note: `/tmp/mudsnote-visual-qa-call-recordings-final2/visual-qa-library/Notes/lz合集.md`
  - visual inspection confirmed `Call Recordings 2` appears above the `iCloud` header and the compact toolbar remains unchanged.

## Decisions

- This is a local Markdown smart source, not an Apple/iCloud call-recording integration.
- Do not add a new disk scan for this UI affordance; keep it derived from the existing note list/search snapshots.
- Keep the existing compact toolbar constants unchanged.

## Next

- Continue source hierarchy and note-list visual tuning from the final QA output; remaining visible gaps are row/icon weighting, editor horizontal positioning, and richer note-list sample parity.
