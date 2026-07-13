# Design QA: source row selection geometry

## Evidence

- Expanded reference/current: `/tmp/mudsnote-source-highlight-probe-209/apple-notes-reference-normalized.png` and `/tmp/mudsnote-source-highlight-probe-209/mudsnote-library.png`
- Expanded comparison: `/tmp/mudsnote-source-highlight-probe-209/apple-notes-vs-mudsnote.png`
- Collapsed comparison: `/tmp/mudsnote-source-highlight-collapsed-209/apple-notes-vs-mudsnote.png`
- State: dark appearance, canonical `921x613pt`, `2x`, All iCloud selected, pointer outside static comparison

## Review

- P0: none
- P1: none
- P2: none
- Apple Notes and Mudsnote selected source surfaces both occupy `x=36...395px`, width `360px`, height `64px` at `2x`.
- Selection and hover share one `LibrarySourceOutlineRowView.highlightBounds`, so pointer feedback uses the same corrected geometry.
- Source icons, labels, counts, native outline indentation, disclosure, drag/drop, and scroll insets are unchanged.
- Collapsed Sidebar Toggle, note-list card, title, and editor origins remain aligned in the collapsed reference state.

## Remaining P3

- Source fill color remains intentionally approximate per user direction; this pass aligns geometry only.

final result: passed
