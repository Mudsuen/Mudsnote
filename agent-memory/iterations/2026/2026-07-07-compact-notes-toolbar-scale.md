# 2026-07-07 Compact Notes toolbar scale

## Request

Continue the active Apple Notes parity goal for Mudsnote after user feedback that an earlier iteration looked closer to Notes, while the current toolbar buttons, window scale, and editor-tools capsule border felt too large or too bright.

## Baseline

- Branch: `main`
- HEAD before work: `074815c Align library toolbar buttons with Notes`
- Dirty files before work: none
- Visual reference from user: early toolbar capsule with subtle/no obvious white border.

## Changes

- Reduced default/presented library window sizes so direct app launch opens a lighter Notes-style library window instead of an oversized canvas.
- Reverted standard toolbar command buttons to native borderless `NSToolbarItem` image presentation, removing the custom 38pt circular button views that made the toolbar feel oversized.
- Restored the closer earlier Notes density for source/list/editor typography: smaller source icons and labels, narrower note column, shorter note rows, tighter note-cell insets, and smaller editor title/body fonts.
- Kept the editor-tools toolbar as a compact capsule but reduced its border to a weak 0.6pt line with low alpha, matching the earlier screenshot where the white edge was not prominent.
- Added regression coverage for native toolbar button presentation, editor-tools capsule border width/alpha, and the compact note-cell density.

## Verification

- Commands run:
  - `swift test --filter 'MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|MarkdownRichEditorTests/libraryToolbarUsesNotesLikeDisabledStates'`
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-compact-toolbar-final`
  - `swift test --filter 'MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|MarkdownRichEditorTests/libraryToolbarUsesNotesLikeDisabledStates'`
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-compact-scale-final`
  - `swift test`
- App/page/package actually opened:
  - `/Applications/Mudsnote.app` via the visual QA harness.
- Result:
  - Targeted toolbar/layout tests passed.
  - Full `swift test` passed with 91 tests.
  - Final visual QA captured `/tmp/mudsnote-visual-qa-compact-scale-final/apple-notes-vs-mudsnote.png`.
- Not verified:
  - iOS real-device validation is intentionally out of scope for the current goal.

## Decisions

- Use `23f954b Align library shell closer to Notes` as the local baseline for visual density, but keep the smaller window size requested by the user instead of restoring that commit's larger window dimensions.
- Keep a very faint capsule outline rather than removing the border entirely, so the toolbar group remains legible on dark material without the prominent white rim.

## Next

- Continue parity work on the remaining visible gaps: source sidebar hierarchy/counts, note-list content grouping, toolbar placement, editor empty/loading states, and closer search/menu button behavior.
