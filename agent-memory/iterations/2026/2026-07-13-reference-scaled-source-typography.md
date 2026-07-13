# Reference-scaled source typography

## Problem

The source pane had already reached the Apple Notes pane width and `32pt` row rhythm, but its labels, section headings, and symbols still appeared oversized and too heavy.

## Evidence

Vision OCR on equal-scale expanded screenshots measured the current `Notes`, `Resources`, and `Archives` labels about `14–16%` wider than the Apple Notes reference.

## Change

- Reduced source row labels from `15pt` to `13.5pt`.
- Changed selected and unselected source labels to regular weight; selection remains clear through the native row background and accent color.
- Reduced source section headings from `13.5pt` to `12pt`.
- Reduced source symbols from `16pt` to `15pt`.
- Preserved the source pane width, row width, `32pt` row height, insets, and count typography.

## Verification

- Focused source/library layout test passed.
- Full `swift test` passed.
- Packaged and signed `/Applications/Mudsnote.app`.
- Installed create/save/search/trash/restore/move/attachment/relaunch smoke passed at `/tmp/mudsnote-library-smoke-188`.
- Final comparison: `/tmp/mudsnote-source-typography-188-final/apple-notes-vs-mudsnote.png`.
- Final OCR width differences are about `1.3%` for Notes, `0.9%` for Resources, and `3.6%` for Archives and Recently Deleted.

## Durable rule

Do not change pane or row geometry to correct a typography-only mismatch. Measure text widths at equal scale and tune font size/weight independently.
