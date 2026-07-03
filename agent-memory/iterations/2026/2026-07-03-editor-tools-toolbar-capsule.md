# 2026-07-03 Editor Tools Toolbar Capsule

## Request

Continue the active macOS Apple Notes parity goal for Mudsnote, with iOS real-device validation removed from scope.

## Baseline

- Branch: `main`
- HEAD: `d125a9b`
- Dirty files before work: none

## Changes

- Replaced the default five separate library toolbar editing items with one Notes-like `editor-tools` capsule.
- Kept the underlying actions for format, checklist, table, link, and attachment unchanged inside the group.
- Preserved the old single-item toolbar identifiers as allowed items and validation targets, but made the grouped item the default visual contract.
- Synced the grouped toolbar buttons' enabled state with the current document state, including empty libraries and trash scope.
- Improved the format menu popover anchor when it is opened from the grouped toolbar button.

## Verification

- Focused tests passed:
  - `swift test --filter MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote`
  - `swift test --filter MarkdownRichEditorTests/libraryToolbarUsesNotesLikeDisabledStates`
  - `swift test --filter MarkdownRichEditorTests/libraryWindowEditorToolbarInsertsRichMarkdownTools`
- `swift test` passed with 86 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- `./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-editor-tools-capsule` passed.
- Packaged-app visual QA confirmed an on-screen `Mudsnote 笔记` window at `1840x978`; comparison image:
  `/tmp/mudsnote-visual-qa-editor-tools-capsule/apple-notes-vs-mudsnote.png`

## Decisions

- Keep the grouped toolbar lightweight and native AppKit-based. This improves Notes visual parity without adding a custom toolbar framework.
- Do not reintroduce iOS validation into this macOS Notes-parity loop.

## Next

- Tune toolbar icon spacing and disabled-state contrast against the Apple Notes reference.
- Continue source-list hierarchy and editor top-rhythm visual polish.
