# 2026-07-09 toolbar compact baseline relock

## Request

Continue the Apple Notes parity goal after the user pointed out that the earlier toolbar version looked closer, especially because the editor-tools buttons and capsule did not have an obvious bright rim or oversized feel.

## Baseline

- Branch: `main`
- HEAD before work: `ae1e44c Tune Notes source list count hierarchy`
- Dirty files before work: none
- Reference version: `b1af277 Lock compact Notes toolbar baseline`
- Current compact shell constants already match the earlier locked baseline: `1420x860` window, `184x32` editor-tools capsule, `30x28` share/more buttons, and `19pt` toolbar symbols.

## Changes

- Restored the editor-tools disabled state to the earlier whole-capsule fade (`0.42`) instead of leaving the capsule fully opaque and only dimming icons.
- Kept standalone share/export and more buttons on icon-level enabled/disabled tinting so their disabled states remain clear without adding chrome.
- Added a separate editor-tool disabled icon tint constant so the whole-capsule fade does not double-dim the symbols.
- Updated the Apple Notes parity roadmap to make whole-capsule disabled fade part of the toolbar baseline.

## Verification

- Passed `swift test --filter MarkdownRichEditorTests/libraryToolbarUsesNotesLikeDisabledStates` (1 test).
- Passed full `swift test` (101 tests).
- Passed `git diff --check`.
- Passed `./scripts/package_app.sh`; installed `/Applications/Mudsnote.app`.
- Passed isolated empty-note visual QA:
  - comparison: `/tmp/mudsnote-visual-qa-toolbar-compact-baseline-relock-final/apple-notes-vs-mudsnote.png`
  - captured window bounds: `1420x860`
  - confirmed the editor-tools group keeps the compact dark capsule without a visible rim.

## Decisions

- The visually closer version is the compact toolbar line around `b1af277`, not the earlier large-canvas `0963441` state.
- Do not enlarge toolbar controls or reintroduce visible capsule rims while continuing Notes parity.

## Next

- Continue with source/list/editor typography and pane-density deltas without loosening the compact toolbar baseline.
