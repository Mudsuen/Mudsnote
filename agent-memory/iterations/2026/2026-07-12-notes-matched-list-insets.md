# 2026-07-12 Notes-matched list insets

## Request

Continue aligning Mudsnote's macOS interface with Apple Notes while preserving the lightweight, high-performance architecture.

## Baseline

- Branch: `main`
- HEAD: `7b5be8c`
- Existing iOS companion changes remained user-owned and out of scope.

## Changes

- Measured the collapsed `304x292pt` state against the checked-in Apple Notes reference.
- Moved group headings from `10pt` to `20pt`.
- Moved selection and hover leading edges from `10pt` to `15pt` while retaining scrollbar clearance.
- Moved note text from `36pt` to `40pt` and bounded separators to `42/28pt`.
- Kept the `200pt` note pane and all vertical geometry unchanged.

## Verification

- Focused three-pane structure test passed.
- Full `swift test` passed.
- `./scripts/package_app.sh` packaged and installed `/Applications/Mudsnote.app`.
- Strict code-sign verification passed.
- Collapsed comparison: `/tmp/mudsnote-collapsed-165b/apple-notes-vs-mudsnote.png`.
- Expanded comparison: `/tmp/mudsnote-expanded-165/apple-notes-vs-mudsnote.png`.
- Both states retain unclipped text, stable scrollbar clearance, and aligned list baselines.

## Decisions

- Tune group headings, row backgrounds, text, and separators independently instead of moving the entire table.

## Next

- Continue with titlebar active-state capture stability and editor content-state fidelity.
