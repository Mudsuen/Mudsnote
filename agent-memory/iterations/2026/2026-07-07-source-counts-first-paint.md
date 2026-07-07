# 2026-07-07 Source counts first paint

## Request

Continue the active macOS Apple Notes parity goal by improving the Mudsnote library shell against the Apple Notes reference while keeping startup lightweight.

## Baseline

- Branch: `main`
- HEAD before work: `f5e0686 Align Notes shell labels`
- Dirty files before work: none
- Visual symptom: `/tmp/mudsnote-visual-qa-notes-english-shell-final-installed/apple-notes-vs-mudsnote.png` showed source-list counts missing for `All iCloud` and the main notes folder on first visual capture, while Apple Notes shows counts in the sidebar.

## Changes

- Deferred library launch now uses its existing lightweight recent-note snapshot to populate source-list counts immediately, instead of leaving source counts blank until the full background snapshot completes.
- Source-row rebuild now reapplies the latest count snapshot and selection state immediately after replacing rows, so folder/tag async loads do not clear visible counts.
- Source count overlays now have identifiers and are explicitly positioned above the source row button, keeping count labels visible on selected rows.
- Added tests for:
  - source count overlay ordering on the selected `All iCloud` row
  - count preservation after tag source rows load
  - count preservation after folder source rows load
  - deferred library launch showing `All iCloud` count immediately

## Verification

- Commands run:
  - `swift test --filter 'MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|MarkdownRichEditorTests/libraryWindowLoadsTagRowsAfterShellIsVisible|MarkdownRichEditorTests/libraryWindowShowsNestedFoldersInSourceList'`
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-source-counts-stable`
  - `swift test --filter 'MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|MarkdownRichEditorTests/libraryWindowLoadsTagRowsAfterShellIsVisible|MarkdownRichEditorTests/libraryWindowShowsNestedFoldersInSourceList|MarkdownRichEditorTests/libraryWindowDeferredShowLoadsFirstNoteWithoutFocusingSearch'`
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-source-counts-stable-final`
  - `swift test`
- App/page/package actually opened:
  - `/Applications/Mudsnote.app` via the visual QA harness.
- Result:
  - Targeted tests passed.
  - Full `swift test` passed with 91 tests.
  - Final visual QA captured `/tmp/mudsnote-visual-qa-source-counts-stable-final/apple-notes-vs-mudsnote.png`, with sidebar counts visible on first capture.
- Not verified:
  - iOS real-device validation remains out of scope for the current macOS Apple Notes parity goal.

## Next

- Continue visible shell parity: toolbar horizontal placement, note-list sample state alignment, sidebar section rhythm, and tighter editor/list width balance.
