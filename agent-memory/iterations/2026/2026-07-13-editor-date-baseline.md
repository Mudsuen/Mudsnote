# 2026-07-13 Editor date baseline

## Request

Continue Apple Notes visual alignment while preserving already verified editor title/body geometry.

## Baseline

- Branch: `main`
- HEAD: `a62a5b9`
- Dirty files before work: concurrent iOS capture/editor changes; excluded from this macOS pass.

## Changes

- Measured the editor date in normalized empty and content captures at `y=136.5px`, versus Apple Notes `y=123.0px`.
- Confirmed the collapsed editor title was already within `2px` vertically.
- Redistributed the invariant `17pt` before-title offset from `13pt + 4pt` to `6.25pt + 10.75pt`, moving only the date row upward by `6.75pt`.
- Added a regression for the individual values and invariant sum.

## Verification

- Focused layout regression and full `swift test` passed.
- `./scripts/package_app.sh` installed `/Applications/Mudsnote.app`; strict deep signature verification passed.
- Installed smoke passed at `/tmp/mudsnote-library-smoke-197-editor-date`, including save, trash/restore, folder move, attachment copy, and attachment reload.
- Empty state: Apple Notes and Mudsnote date both begin at `y=123.0px`.
- Content state: Apple Notes and Mudsnote date both begin at `y=123.0px`.
- Collapsed title regression: Apple Notes `y=186px`; Mudsnote `y=184px`, unchanged from before this iteration.
- Empty evidence: `/tmp/mudsnote-visual-qa-197-empty-date/apple-notes-vs-mudsnote.png`.
- Content evidence: `/tmp/mudsnote-visual-qa-197-content-date/apple-notes-vs-mudsnote.png`.
- Collapsed evidence: `/tmp/mudsnote-visual-qa-197-collapsed-title/apple-notes-vs-mudsnote.png`.

## Decisions

- Preserve cumulative layout offsets when downstream content is aligned; adjust the local row origin and following spacing together.

## Next

- Continue with the next largest non-intentional mismatch in the normalized visual evidence.
