# 2026-07-08 hide empty Tags placeholder

## Request

Continue the Apple Notes parity goal with UI alignment first and performance kept lightweight.

## Baseline

- Branch: `main`
- HEAD before work: `16e190d Stabilize Notes visual QA fixture`
- Dirty files before work: none
- Visual baseline: `/tmp/mudsnote-visual-qa-fixture-state-final/apple-notes-vs-mudsnote.png` showed a visible `No Tags` placeholder under the Tags header, while the Apple Notes reference only shows the Tags header when there are no tags.

## Changes

- Removed the visible empty-tags placeholder from the source sidebar.
- Kept the Tags header and the existing tag-row behavior for libraries that actually contain tags.
- Added regression coverage for the empty-tags source list state so `No Tags` does not reappear.

## Verification

- Commands run before final verification:
  - `swift test --filter 'MarkdownRichEditorTests/libraryWindowHidesEmptyTagPlaceholderLikeAppleNotes|MarkdownRichEditorTests/libraryWindowLoadsTagRowsAfterShellIsVisible|MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote'`
- Final verification:
  - `swift test`
  - `git diff --check`
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-empty-tags-final`
- Result:
  - Full `swift test` passed with 95 tests.
  - `git diff --check` passed.
  - Final visual QA captured `/tmp/mudsnote-visual-qa-empty-tags-final/apple-notes-vs-mudsnote.png`.
  - The final screenshot no longer shows `No Tags` under the Tags header.
  - Installed app refreshed at `/Applications/Mudsnote.app`.

## Decisions

- Follow Apple Notes' quieter empty-state treatment in the source list: show the section header, not an extra explanatory placeholder.
- Keep source-tag discovery lazy so this UI cleanup does not add startup work.

## Next

- Continue visible shell parity against the stable fixture: source/sidebar scale, toolbar placement, selected-row geometry, and editor date/title spacing.
