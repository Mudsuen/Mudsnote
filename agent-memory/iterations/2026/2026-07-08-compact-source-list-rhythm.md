# 2026-07-08 Compact source-list rhythm

## Request

Continue the active Mudsnote Apple Notes parity goal, using the earlier more Notes-like compact toolbar version as the visual baseline and avoiding oversized controls.

## Baseline

- Branch: `main`
- HEAD before work: `332573d Match Notes row metadata layout`
- Dirty files before work: none
- Visual baseline: `/tmp/mudsnote-visual-qa-note-row-metadata-final/apple-notes-vs-mudsnote.png` showed the compact, borderless toolbar direction was already closer to the requested earlier version, while the source-list rhythm still needed a smaller Notes-like density lock.

## Changes

- Kept the editor tools toolbar on the earlier compact, borderless capsule treatment.
- Tightened source-list density:
  - 36pt source rows
  - smaller source icons and disclosure chevrons
  - smaller source labels and counts
  - tighter source row and section spacing
- Added regression expectations so future iterations do not accidentally reintroduce an oversized editor-tools capsule or enlarged source-list rows.
- Updated the Apple Notes parity roadmap with the compact source-list rhythm requirement.

## Verification

- Commands run:
  - `swift test --filter 'MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|MarkdownRichEditorTests/librarySourceListDisplaysDefaultNotesFolderLikeAppleNotes|MarkdownRichEditorTests/librarySourceListShowsZeroCountsForEmptyFoldersLikeAppleNotes|MarkdownRichEditorTests/libraryWindowShowsNestedFoldersInSourceList'`
  - `swift test`
  - `git diff --check`
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-compact-source-list-final`
- App/package actually opened:
  - `/Applications/Mudsnote.app` via the visual QA harness after packaging.
- Result:
  - Focused layout/source-list tests passed.
  - Full `swift test` passed with 98 tests.
  - `git diff --check` passed.
  - Packaged app refreshed at `/Applications/Mudsnote.app`.
  - Final visual QA captured `/tmp/mudsnote-visual-qa-compact-source-list-final/apple-notes-vs-mudsnote.png`.
  - Final metadata recorded `mudsnote_window_bounds=x=46,y=78,width=1420,height=860` and `frontmost_before_capture=Mudsnote`.
  - Visual inspection confirmed the source list is tighter and the editor tools toolbar remains borderless/compact.
- Not verified:
  - iOS real-device validation remains intentionally out of scope for the current macOS Notes-parity goal.

## Decisions

- Treat `a925b48 Remove Notes toolbar capsule rim` and `86ce4c7 Tighten Notes toolbar scale` as the toolbar-size/style baseline.
- Keep this pass visual-only and local: no data-model, indexing, or note-loading behavior changes.

## Next

- Run focused tests, full tests, packaging, installed-app visual QA, then inspect the side-by-side screenshot for remaining size mismatches.
