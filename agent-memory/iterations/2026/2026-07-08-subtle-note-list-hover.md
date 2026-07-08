# 2026-07-08 subtle note-list hover

## Request

Continue the active Apple Notes parity goal for Mudsnote, prioritizing UI alignment while keeping the app lightweight and performant.

## Baseline

- Branch: `main`
- HEAD before work: `a925b48 Remove Notes toolbar capsule rim`
- Dirty files before work: none
- Visual baseline: `/tmp/mudsnote-visual-qa-editor-tools-borderless-final/apple-notes-vs-mudsnote.png` showed an extra visible gray hover block in the note list, which was not part of the Apple Notes reference state.

## Changes

- Reduced note-list hover fill from a high-contrast gray card to a low-alpha hover surface so it no longer competes with the selected golden note card.
- Added a regression assertion that the note-list hover fill stays below high-contrast selection-like opacity.
- Updated the visual QA harness to move the pointer outside the window before capture, preventing cursor hover from polluting static Apple Notes comparisons.
- Documented the low-contrast hover and pointer-normalized visual QA state in the parity roadmap.

## Verification

- Commands run:
  - `swift test --filter 'MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|MarkdownRichEditorTests/libraryNoteScrollViewFitsSingleColumnToVisibleWidth'`
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-subtle-note-hover`
  - `swift test`
  - `git diff --check`
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-subtle-note-hover-final`
- App/package actually opened:
  - `/Applications/Mudsnote.app` via the visual QA harness.
- Result:
  - Focused tests passed.
  - Full `swift test` passed with 91 tests.
  - `git diff --check` passed.
  - Final packaged visual QA passed and captured `/tmp/mudsnote-visual-qa-subtle-note-hover-final/apple-notes-vs-mudsnote.png`.
  - Installed app refreshed at `/Applications/Mudsnote.app`.
  - The hover block no longer appears in the static note-list comparison state.
- Not verified:
  - iOS real-device validation remains intentionally out of scope for the current macOS Notes-parity goal.

## Decisions

- Keep hover feedback for real pointer use, but make it substantially quieter than selection. The Notes reference state should be about selected row hierarchy, not accidental pointer location.
- Fix the visual QA harness instead of relying on manual pointer placement before every screenshot.

## Next

- Continue with source-sidebar hierarchy rhythm, toolbar horizontal placement, and closer note-list sample-state parity against the Apple Notes reference.
