# 2026-07-07 borderless editor-tools capsule

## Request

Continue the Apple Notes parity goal after user feedback that an earlier toolbar version looked closer, especially because the editor-tools button group did not have a prominent white outline.

## Baseline

- Branch: `main`
- HEAD before work: `d0efa05 Stabilize Notes source counts`
- Dirty files before work: none
- Reference: user-provided crop of the Notes-style `Aa / checklist / table / link / paperclip` toolbar group with a subtle dark capsule and no obvious white rim.

## Changes

- Changed the library editor-tools capsule from a faint separator border to a borderless dark-fill surface.
- Preserved the compact current button sizing, symbol sizing, disabled alpha, and toolbar item ordering.
- Added regression coverage for enabled/disabled fill alpha and zero border alpha so the capsule does not drift back to a high-contrast outline.
- Stabilized the autosave regression test by flushing the pending save directly after verifying the UI enters the `正在保存...` state, avoiding MainActor timer starvation during the full concurrent test run.

## Verification

- Commands run:
  - `swift test --filter 'MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|MarkdownRichEditorTests/libraryToolbarUsesNotesLikeDisabledStates'`
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-borderless-editor-tools-fill`
  - `swift test --filter 'MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|MarkdownRichEditorTests/libraryToolbarUsesNotesLikeDisabledStates|MarkdownRichEditorTests/libraryWindowAutosavesEditedExistingNote'`
  - `swift test`
  - `git diff --check`
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-editor-tools-borderless-final`
- App/package actually opened:
  - `/Applications/Mudsnote.app` via the visual QA harness.
- Result:
  - Targeted toolbar/autosave tests passed.
  - Full `swift test` passed with 91 tests.
  - Final visual QA captured `/tmp/mudsnote-visual-qa-editor-tools-borderless-final/apple-notes-vs-mudsnote.png`.
  - Installed app refreshed at `/Applications/Mudsnote.app`.
- Not verified:
  - iOS real-device validation remains intentionally out of scope for this goal.

## Decisions

- Do not roll back the whole UI to the earlier commit, because later fixes for direct library launch, source counts, and shell labels should stay.
- Keep the current compact toolbar and window sizing for now; the early constants showed the older Notes-like pass actually targeted a larger 1840-wide window, while the user feedback specifically pointed at the toolbar capsule edge.

## Next

- Continue with toolbar horizontal placement, source-sidebar hierarchy rhythm, and note-list sample-state parity against the Apple Notes reference.
