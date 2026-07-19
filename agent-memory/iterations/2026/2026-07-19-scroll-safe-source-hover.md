# Scroll-safe source hover

## Problem

Source folder and tag rows independently retained hover state. When the outline scrolled under a stationary pointer, AppKit did not reliably deliver every tracking-area exit, leaving several gray hover surfaces visible.

## Change

- `LibrarySourceOutlineView` now owns one weak hovered row.
- Entering a row clears the previous owner before painting the next row.
- `LibrarySourceScrollView` reconciles hover from the current pointer and the outline's visible rectangle whenever the clip view scrolls.
- Reconciliation never creates offscreen rows and clears hover over headings, empty space, or outside the visible outline.

## Durable rule

Source and note hover are container-owned pointer state. Do not restore independent accumulated row hover state for reusable scrolling lists.
