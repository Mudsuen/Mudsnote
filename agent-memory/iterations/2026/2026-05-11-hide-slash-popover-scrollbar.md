# 2026-05-11 Hide Slash Popover Scrollbar

## Request

The rebuilt slash command popup layout is correct; hide the right-side scrollbar.

## Changes

- Removed the visible vertical scroller from the slash suggestion scroll view.
- Removed the extra right-side scroller gutter so the popup width equals the measured content width.
- Updated the compact sizing regression test to assert no visible vertical scroller and no scroller gutter.

## Verification

- `swift test --filter MarkdownRichEditorTests.slashSuggestionPopoverUsesCompactMenuSizing`
- `swift test`
- `./scripts/package_app.sh`
