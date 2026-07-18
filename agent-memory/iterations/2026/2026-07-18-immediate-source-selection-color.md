# Immediate source-selection color

## Problem

The source outline selected a clicked row before its delegate ran, but custom yellow title styling used `selectedScope`. `activateSourceScope` saved dirty editor content synchronously before assigning that new scope, so the old row kept the yellow title until persistence completed.

## Fix

- Derive source-cell selected styling from `sourceOutlineView.selectedRowIndexes` whenever the item has a visible row.
- Refresh visible source cells at the start of `outlineViewSelectionDidChange`, before calling the save-backed scope activation path.
- Keep `selectedScope` assignment after successful save; `refreshSourceSelection` still restores the old visual selection on failure.

## Verification boundary

The source keyboard/navigation test dirties the current note, switches sources, and inspects the newly selected row's text color from inside `onSave`. The color must already equal `LibrarySourceSelectionPalette.foregroundColor` before the synchronous save callback returns.
