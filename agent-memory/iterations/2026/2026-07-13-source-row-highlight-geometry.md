# 2026-07-13 source row highlight geometry

## Request

Continue Apple Notes desktop parity after the native icon audit, using rendered evidence and preserving the optimized source-outline architecture.

## Baseline

- Branch: `main`
- HEAD: `75b5cc6`
- Dirty files before work: none at the first checkpoint; concurrent iOS work resumed before documentation and was left untouched

## Changes

- Added independent source-row highlight insets of `10pt` leading, `10pt` trailing, and `0pt` vertical.
- Stopped reusing the source scroll view's `14/6pt` content insets for row selection and hover drawing.
- Kept the shared highlight path, corner radius, content layout, outline hierarchy, and pointer behavior unchanged.

## Verification

- Focused macOS layout regression and the full `154`-test macOS suite passed.
- Production packaging installed `/Applications/Mudsnote.app`; strict signature verification passed.
- Expanded selected surface matches Apple Notes exactly at `x=36...395px`, `360x64px` at `2x`.
- Expanded comparison: `/tmp/mudsnote-source-highlight-probe-209/apple-notes-vs-mudsnote.png`.
- Collapsed comparison: `/tmp/mudsnote-source-highlight-collapsed-209/apple-notes-vs-mudsnote.png`.

## Decisions

- Keep scroll content padding and row highlight geometry as separate layout contracts.
- Reuse the exact corrected bounds for hover and selection so pointer and selected states cannot drift apart.
- Do not adjust approximate colors in this geometry iteration.

## Next

- Continue with the next state-backed Apple Notes workflow or performance gap.
