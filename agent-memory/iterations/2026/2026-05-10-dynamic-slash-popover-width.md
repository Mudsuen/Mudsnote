# 2026-05-10 Dynamic Slash Popover Width

## Request

The slash command popover's outer black box was still too wide. It should fit the longest command title instead of using a broad fixed width.

## Baseline

- Started from `026ac21 Make slash popover opaque and left aligned`.

## Changes

- Replaced the fixed slash suggestion popover width with a measured width based on the widest visible title.
- Removed the hidden icon gap for rows without icons so slash command text stays close to the left edge.
- Kept the popover opaque and borderless, with only compact row highlighting.

## Verification

- `swift test --filter MarkdownRichEditorTests.slashSuggestionPopoverUsesCompactMenuSizing`
- `swift test`
- `./scripts/package_app.sh`
- `/Applications/Mudsnote.app --args --floating-note`
