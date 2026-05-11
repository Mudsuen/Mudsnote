# 2026-05-11 Rebuild Slash Popover List

## Request

The slash command popup still showed clipped/offset selection despite prior portal and padding fixes. Re-examine the mechanism and make a durable fix.

## Diagnosis

- The popup was portaled above the editor, but its internal list still used `NSTableView`, `NSTableColumn`, and an `NSScrollView` legacy scroller.
- That kept implicit table/clip/scroller layout in the path, which could still crop the selected row or make spacing look like an empty leading slot.
- Slash command positioning was still anchored to the current caret after the query text, so `/heading` could shift the menu to the right instead of staying aligned to the slash token.

## Changes

- Replaced the table-backed suggestion rows with a custom drawn `SuggestionListView`.
- Kept the list content width separate from the scroller gutter, without a table column.
- Drew the selected row inset inside the content bounds so both rounded corners remain visible.
- Continued hosting the popup at the window content level.
- Anchored slash-command popups to the replacement token start, not the current caret after the typed query.
- Updated regression tests to verify the custom list sizing and slash-token anchoring.

## Verification

- `swift test --filter MarkdownRichEditorTests.slashSuggestionPopoverUsesCompactMenuSizing --filter MarkdownRichEditorTests.inlineSuggestionPopoverIsHostedAtWindowContentLevel`
- `swift test`
- `./scripts/package_app.sh`
- `/Applications/Mudsnote.app --args --floating-note`
