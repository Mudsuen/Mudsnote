# Rendered-Width Source Sidebar

## Request

Continue Apple Notes visual parity without disturbing user-customized pane sizes.

## Baseline

- Branch: `main`
- HEAD: `ccd09d1`
- Pre-existing dirty files: iOS companion work only; untouched by this iteration.

## Changes

- Reduced the source-column logical default and minimum from `212pt` to `205pt`.
- Reduced source rows from `184pt` to `180pt` and changed horizontal source insets to `14/11pt`.
- Advanced the layout scale to version 7.
- Version 7 clears only exact stored `212/200pt` source/list defaults; customized widths remain intact.

## Verification

- Focused layout and migration tests passed.
- Full `swift test` passed.
- `git diff --check` passed.
- Repackaged and launched `/Applications/Mudsnote.app`.
- Strict code-sign verification passed.
- Expanded comparison: `/tmp/mudsnote-source-width-176/apple-notes-vs-mudsnote.png`.
- The rendered source edge is within about `3pt` of Apple Notes, improved from roughly `10pt`, and source rows match the reference density.

## Decisions

- Calibrate native pane constants against the rendered divider, including AppKit-owned sidebar geometry.
- Migrate only exact prior defaults; never overwrite manually resized panes.

## Next

- Continue from state-matched rendered measurements and avoid tuning typography from mismatched Chinese/English glyph samples.
