# 2026-07-07 Notes English shell labels

## Request

Continue the active Apple Notes parity goal by making the current Mudsnote library window visually closer to the supplied Apple Notes reference while keeping the implementation lightweight and verified in the installed macOS app.

## Baseline

- Branch: `main`
- HEAD before work: `0963441 Rebalance Notes toolbar scale`
- Dirty files before work: none
- Visual baseline: `/tmp/mudsnote-visual-qa-next-baseline/apple-notes-vs-mudsnote.png`

## Changes

- Changed the library search placeholder, tooltip, and accessibility label to Apple Notes-style English (`Search`, `Search Notes`).
- Changed the visible note-list header counts to `note/notes` and `result/results`, and removed the noisy visible `Indexing...` suffix from the toolbar title area.
- Changed recency section labels to `Today`, `Yesterday`, `Previous 7 Days`, and `Previous 30 Days`.
- Changed note-row metadata dates to Notes-like display:
  - same day: `HH:mm`
  - yesterday: `Yesterday`
  - previous week: weekday name
  - older notes: `M/d/yy`
- Changed trash note-row metadata to use `Recently Deleted` instead of the previous Chinese folder label.
- Changed the editor status date to `MMMM d, yyyy at HH:mm` with a fixed English locale.
- Changed library empty/loading strings that can appear in the main shell to English equivalents.
- Updated regression tests for the visible shell labels, count strings, group label, editor date, and row metadata.

## Verification

- Commands run:
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-next-baseline`
  - `swift test --filter 'MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|MarkdownRichEditorTests/libraryAllNotesIncludesPlainMarkdownOutsideRecents|MarkdownRichEditorTests/libraryWindowSearchScopesAndHighlightsMatches|MarkdownRichEditorTests/librarySearchFieldDebouncesTypingButFlushesKeyboardActions|MarkdownRichEditorTests/libraryWindowDeletesRestoresAndPermanentlyDeletesNotes|MarkdownRichEditorTests/libraryWindowLoadsTagRowsAfterShellIsVisible|MarkdownRichEditorTests/libraryWindowShowsNestedFoldersInSourceList|MarkdownRichEditorTests/libraryWindowDeferredShowLoadsFirstNoteWithoutFocusingSearch'`
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-english-shell-labels`
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-notes-english-dates-final`
  - `swift test`
- App/page/package actually opened:
  - `/Applications/Mudsnote.app` via the visual QA harness.
- Result:
  - Targeted tests passed.
  - Full `swift test` passed with 91 tests.
  - Final visual QA captured `/tmp/mudsnote-visual-qa-notes-english-dates-final/apple-notes-vs-mudsnote.png`.
- Not verified:
  - iOS real-device validation remains intentionally out of scope for this macOS Apple Notes parity goal.

## Notes

- Source-list counts can still appear after the background count snapshot refresh; a later polish pass should make those counts stable in the first visual QA capture without reintroducing a visible indexing label.

## Next

- Continue on shell parity gaps: source-list count stability, toolbar horizontal placement, note-list demo state alignment, and tighter sidebar/sidebar-title rhythm.
