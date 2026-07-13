# 2026-07-13 native icon optical audit

## Request

Continue checking icon fidelity after the expanded Add Folder and Sidebar Toggle correction, keeping all controls native and Apple Notes-like.

## Baseline

- Branch: `main`
- HEAD at edit start: `411e3b3`; concurrent iOS work advanced HEAD to `7bb9404`
- Dirty files before work: concurrent iOS files, left untouched

## Changes

- Separated New Note's `13pt` symbol from the collapsed Sidebar Toggle's retained `12pt` symbol.
- Changed grouped editor symbols from `14pt` to `13pt` and native Aa from `13pt` to `17pt`.
- Expanded source-row image slots from `18x18pt` to `22x20pt`, with a measured `7.5pt` inset and `3pt` title gap, so the existing `15pt` SF Symbols are not downscaled.
- Applied the same source geometry to inline folder editing.

## Verification

- Focused macOS layout regression and the full `154`-test macOS suite passed.
- Production packaging installed `/Applications/Mudsnote.app`; strict signature verification passed.
- Expanded `2x` QA: `/tmp/mudsnote-all-icons-probe-208/apple-notes-vs-mudsnote.png`.
- Collapsed QA: `/tmp/mudsnote-editor-toolbar-icons-collapsed-208/apple-notes-vs-mudsnote.png`.
- Real-pointer hover: `/tmp/mudsnote-window-hover-crop-208.png`.
- New Note/Table/Attachment match exact visible reference dimensions; Checklist and Aa remain within two pixels.

## Decisions

- Keep system search-field icon sizing untouched when native output is already within two pixels.
- Preserve source title origins and icon trailing edges instead of widening the folder glyph by three pixels and shifting aligned text.
- Treat symbol point size, image canvas, image-view slot, and visible pixel boundary as independent layers.

## Next

- Continue Apple Notes parity from the next state-backed visual or workflow gap rather than globally changing icon sizes.
