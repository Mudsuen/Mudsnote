# 2026-07-08 compact Notes toolbar baseline

## Request

Continue the Apple Notes parity goal after user confirmed the earlier toolbar version looked closer, especially the compact editor-tools capsule with no obvious white rim.

## Baseline

- Branch: `main`
- HEAD before work: `d3d09aa Match empty Notes tags header`
- Dirty files before work: none
- Visual baseline: keep the `0963441` compact toolbar scale and `a925b48` borderless capsule direction instead of returning to oversized or high-rim toolbar controls.

## Changes

- Kept the current borderless dark editor-tools capsule treatment.
- Tightened the editor-tools group from `200x36` to `192x34` so the toolbar reads closer to the earlier Apple Notes-like version.
- Reduced each grouped editor-tool button from `39x30` to `37x28`.
- Reduced the shared toolbar symbol size from `21pt` to `20pt` and scaled the custom `Aa` toolbar image down with it.

## Verification

- Commands run:
  - `swift test --filter 'MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|MarkdownRichEditorTests/libraryToolbarUsesNotesLikeDisabledStates|MarkdownRichEditorTests/libraryWindowEditorToolbarInsertsRichMarkdownTools'`
  - `swift test`
  - `git diff --check`
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-compact-toolbar-baseline-final`
- App/package actually opened:
  - `/Applications/Mudsnote.app` via the visual QA harness.
- Result:
  - Focused toolbar/editor tests passed.
  - Full `swift test` passed with 95 tests.
  - `git diff --check` passed.
  - Packaged app refreshed at `/Applications/Mudsnote.app`.
  - Visual QA captured `/tmp/mudsnote-visual-qa-compact-toolbar-baseline-final/apple-notes-vs-mudsnote.png`.
- Not verified:
  - iOS real-device validation remains intentionally out of scope for the current macOS Notes-parity goal.

## Decisions

- Treat the earlier compact, borderless toolbar as the visual baseline for future toolbar work.
- Prefer small constant-level visual corrections over custom toolbar chrome so the app remains native and lightweight.

## Next

- Continue closing visible gaps around source-sidebar hierarchy rhythm, note-list selected card geometry, and editor title/date spacing.
