# 2026-05-10 Slash Popover Selection Fit

## Request

The slash command popover became narrow enough, but the selected row's right rounded corner was clipped and the selected highlight still sat too far from the left edge.

## Changes

- Tightened the selected-row horizontal inset and text leading padding.
- Kept row content in a measured content column, with a small separate gutter only when the vertical scroller is needed.
- Disabled table column autoresizing so the selected background does not expand under the scroller and lose its right rounded corner.

## Verification

- `swift test --filter MarkdownRichEditorTests.slashSuggestionPopoverUsesCompactMenuSizing`
- `swift test`
- `./scripts/package_app.sh`
- `/Applications/Mudsnote.app --args --floating-note`
