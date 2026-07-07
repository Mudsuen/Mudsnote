# 2026-07-07 Notes toolbar borderless icons

## Request

Continue the active macOS Apple Notes parity goal for Mudsnote, prioritizing UI alignment while keeping the app lightweight and responsive. iOS real-device validation remains out of scope for this goal.

## Baseline

- Branch: `main`
- HEAD: `13f77a3 Tighten Notes library visual rhythm`
- Dirty files before work: none
- Visual baseline: `/tmp/mudsnote-visual-qa-continuation-baseline/apple-notes-vs-mudsnote.png`

## Changes

- Converted standard library toolbar command buttons to fixed-size borderless `NSButton` views so new folder, sidebar toggle, and new note read closer to Apple Notes' icon-first toolbar.
- Changed the note-list title toolbar item to a plain unbordered `NSView` wrapper so the scope title no longer looks like a search/control capsule.
- Centralized toolbar item presentation updates so dynamic toggle/delete/restore labels also update the visible custom button image and accessibility label.
- Added regression coverage for unbordered toolbar items, fixed icon-button constraints, and sidebar toggle label propagation.

## Verification

- Commands run:
  - `swift test --filter 'MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|MarkdownRichEditorTests/libraryToolbarUsesNotesLikeDisabledStates'`
  - `swift test --filter 'MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|MarkdownRichEditorTests/libraryToolbarUsesNotesLikeDisabledStates|MarkdownRichEditorTests/libraryWindowSearchScopesAndHighlightsMatches'`
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-toolbar-unbordered`
  - `swift test`
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-toolbar-borderless-final`
- App/page/package actually opened:
  - `/Applications/Mudsnote.app` via the visual QA harness.
- Result:
  - Targeted tests passed.
  - Packaged visual QA captured `/tmp/mudsnote-visual-qa-toolbar-unbordered/apple-notes-vs-mudsnote.png`.
  - Full `swift test` passed with 91 tests.
  - Final packaged visual QA captured `/tmp/mudsnote-visual-qa-toolbar-borderless-final/apple-notes-vs-mudsnote.png`.
- Not verified yet:
  - No manual click-through beyond the visual QA launch; this slice changed toolbar presentation only and is covered by action/state tests.

## Decisions

- Keep menu-style toolbar items such as share/export, more, and the editor tools capsule on their existing system/menu presentations; this slice only removes unwanted borders from title and simple command buttons.
- Use `NSToolbarItem.isBordered = false` as the narrow fix for title/control capsule mismatch instead of moving the title out of the toolbar.

## Next

- Continue toolbar fine tuning against the Apple Notes screenshot, especially title/count placement, menu button scale, and search-field density.
- Continue source-list hierarchy and note-list content-state tuning without expanding beyond local Markdown storage.
