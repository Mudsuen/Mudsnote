# 2026-05-11 Portal Slash Popover

## Request

Revisit the slash command popover using a portal-style fix: avoid parent clipping, handle window bounds, and tighten item padding so the selected row no longer appears offset or clipped.

## Changes

- Moved the inline suggestion popover from the editor shell layer to the window content view layer.
- Reparent the suggestion view during positioning if needed, keeping it above the editor content.
- Continue clamping the floating menu inside the window content bounds.
- Reduced selected-row and text-leading padding to remove the remaining left-side gap.
- Added a regression test that verifies the suggestion popover is hosted at the window content level.

## Verification

- `swift test --filter MarkdownRichEditorTests.slashSuggestionPopoverUsesCompactMenuSizing --filter MarkdownRichEditorTests.inlineSuggestionPopoverIsHostedAtWindowContentLevel`
- `swift test`
- `./scripts/package_app.sh`
- `/Applications/Mudsnote.app --args --floating-note`
