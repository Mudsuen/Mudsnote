# 2026-07-13 reference-sized source toolbar icons

## Request

Correct the visibly oversized Add Folder and Sidebar Toggle icons in the expanded macOS source sidebar while continuing Apple Notes parity.

## Baseline

- Branch: `main`
- HEAD: `8255a6f`
- Dirty files before work: five concurrent iOS files, left untouched

## Changes

- Added a dedicated `13pt` SF Symbol configuration for expanded source actions.
- Applied it during initial toolbar construction, toolbar refresh, and expanded/collapsed source transitions.
- Preserved native `.toolbar` interaction, `30pt` button frames, measured positions, and the collapsed `12pt` glass symbol.

## Verification

- Focused macOS layout regression and the full `154`-test macOS suite passed.
- Production packaging installed `/Applications/Mudsnote.app`; strict signature verification passed.
- Same-size `2x` visual QA passed at `/tmp/mudsnote-source-action-icons-final-207/apple-notes-vs-mudsnote.png`.
- Apple Notes/Mudsnote visible boundaries: folder `44x31px` / `44x30px`; sidebar `38x30px` / `38x30px`.

## Decisions

- Measure visible glyph pixels, not `NSImage.size`, because AppKit preserves a larger symbol canvas around the configured glyph.
- Keep source actions optically independent from generic toolbar and compact glass symbol sizes.

## Next

- Continue per-symbol toolbar review only from equal-scale, same-state visual evidence.
