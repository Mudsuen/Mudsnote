# Scroll-safe note hover and bounded cards

## Problem

Tracking-area exit events were not reliably delivered while the note table scrolled under a stationary pointer. Each traversed row could therefore retain `isPointerHovered`, leaving multiple hover backgrounds visible. Long selected-note titles also used the cell's trailing inset rather than the narrower selected-card edge and could render outside the gold surface.

## Change

- Added one weak `pointerHoveredRow` owner to `LibraryNoteTableView`.
- Entering a row clears the previous hover owner before activating the new row.
- `LibraryNoteScrollView.reflectScrolledClipView` now asks the table to reconcile hover from the current mouse position.
- Reconciliation accepts only points inside `visibleRect`, resolves the row without creating offscreen views, and clears hover outside visible note rows.
- Reduced note text-stack compression resistance and minimum width so narrow list columns can truncate instead of overflowing.
- Moved the text trailing boundary to `31pt`, which is the `21pt` selected-card trailing inset plus `10pt` internal padding.

## Verification

- Focused layout/hover regression passed.
- Full `swift test` passed.
- `/Applications/Mudsnote.app` was repackaged and passed strict code-signature verification.
- Long-title installed screenshot: `/tmp/mudsnote-list-hover-189/long-title.png`.
- Real scroll screenshot: `/tmp/mudsnote-list-hover-189/after-scroll-hover.png`.
- Installed create/save/search/trash/restore/move/attachment/relaunch smoke passed at `/tmp/mudsnote-library-smoke-189-retry`; the first run hit the existing menu-tracking timing flake during restore.

## Durable rule

Treat hover as table-owned pointer state, not accumulated row event state. Constrain text to the visible selection surface whenever that surface is narrower than the table cell.
