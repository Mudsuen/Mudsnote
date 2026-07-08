# 2026-07-08 plain empty Tags header

## Request

Continue the Apple Notes parity goal with UI alignment first while keeping the app lightweight and fast.

## Baseline

- Branch: `main`
- HEAD before work: `58e3ee2 Hide empty Notes tags placeholder`
- Dirty files before work: none
- Visual baseline: `/tmp/mudsnote-visual-qa-empty-tags-final/apple-notes-vs-mudsnote.png` no longer showed `No Tags`, but the empty Tags header still had a disclosure chevron. The Apple Notes reference shows a plain `Tags` header when the section is empty.

## Changes

- Made the Tags source header render as plain text after tag discovery confirms there are no tags.
- Preserved the existing disclosure chevron and collapse behavior when tags actually exist.
- Added regression coverage for the empty Tags header image state and existing non-empty tag source behavior.

## Verification

- Commands run before final verification:
  - `swift test --filter 'MarkdownRichEditorTests/libraryWindowHidesEmptyTagPlaceholderLikeAppleNotes|MarkdownRichEditorTests/libraryWindowLoadsTagRowsAfterShellIsVisible|MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote'`
- Final verification:
  - `swift test`
  - `git diff --check`
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-plain-empty-tags-header-final`
- Result:
  - Full `swift test` passed with 95 tests.
  - `git diff --check` passed.
  - Final visual QA captured `/tmp/mudsnote-visual-qa-plain-empty-tags-header-final/apple-notes-vs-mudsnote.png`.
  - The final screenshot shows a plain `Tags` header without the empty-section disclosure chevron.
  - Installed app refreshed at `/Applications/Mudsnote.app`.

## Decisions

- Keep tag discovery lazy; this is a presentation update after existing background tag loading, not extra startup work.
- Keep tag collapse behavior for non-empty tag lists because it remains useful once tags exist.

## Next

- Continue shell parity against the stable visual fixture: sidebar proportions, toolbar placement, selected-note card geometry, and editor date/title spacing.
