# 2026-07-08 Compact editor rhythm

## Request

Continue the active Mudsnote Apple Notes parity goal, keeping the app lightweight while moving the macOS library/editor UI closer to Apple Notes.

## Baseline

- Branch: `main`
- HEAD before work: `56f0748 Compact Notes list cards`
- Dirty files before work: none
- Visual baseline: `/tmp/mudsnote-visual-qa-compact-note-list-final/apple-notes-vs-mudsnote.png` showed the source list and note list moving toward the earlier compact Notes-like direction, while the editor typography and date/title rhythm still needed lighter side-by-side tuning.

## Changes

- Tightened the library editor rhythm:
  - title font from 36pt to 34pt
  - body font from 17.5pt to 16.5pt
  - code font from 16.5pt to 15.5pt
  - editor horizontal inset from 58pt to 52pt
  - date-to-title spacing from 34pt to 28pt
- Added regression expectations for the compact editor metrics.
- Updated the Apple Notes parity roadmap to describe the compact editor typography direction.

## Verification

- Commands run:
  - `swift test --filter 'MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|MarkdownRichEditorTests/libraryWindowShowsEmptyMarkdownFileAsBlankEditorNewNote|MarkdownRichEditorTests/libraryWindowAutosavesEditedExistingNote|MarkdownRichEditorTests/libraryWindowEditorToolbarInsertsRichMarkdownTools'`
  - `swift test`
  - `git diff --check`
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-compact-editor-final`
- App/package actually opened:
  - `/Applications/Mudsnote.app` via the visual QA harness after packaging.
- Result:
  - Focused editor/layout tests passed.
  - Full `swift test` passed with 98 tests.
  - `git diff --check` passed.
  - Packaged app refreshed at `/Applications/Mudsnote.app`.
  - Final visual QA captured `/tmp/mudsnote-visual-qa-compact-editor-final/apple-notes-vs-mudsnote.png`.
  - Final metadata recorded `mudsnote_window_bounds=x=46,y=78,width=1420,height=860` and `frontmost_before_capture=Mudsnote`.
  - Visual inspection confirmed the shell remained stable; this QA fixture selects an empty note, so the editor typography change is primarily proven by focused tests rather than visible body text in the screenshot.
- Not verified:
  - A dedicated visual QA capture of a non-empty editor note. Add this to the harness before making stronger claims about body/text side-by-side matching.
  - iOS real-device validation remains intentionally out of scope for the current macOS Notes-parity goal.

## Decisions

- Keep this pass visual-only: no note-loading, autosave, search, indexing, or serialization behavior changes.
- Keep the centered date-only header and left-aligned title behavior already established by earlier Notes-parity work.

## Next

- Run focused editor/layout tests, full tests, package the app, and capture installed-app visual QA.
