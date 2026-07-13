# Higher editor content baseline

## Request

Move the library editor title farther upward to match the supplied clear Apple Notes crop.

## Baseline

- Branch: `main`
- HEAD: `affaf71`
- Dirty files before work: none

## Changes

- Reduced the shared editor stack top inset from `12pt` to `6pt`.
- Kept the `20pt` date row, `8pt` date-to-title spacing, `8pt` title-to-body spacing, typography, and horizontal reading edge unchanged.
- Updated the layout contract to pin the new measured value.

## Verification

- Focused library layout test and full `swift test` passed.
- Packaged and strictly signature-verified `/Applications/Mudsnote.app`.
- Installed library smoke passed at `/tmp/mudsnote-installed-library-smoke-184`.
- Content-state visual QA: `/tmp/mudsnote-title-content-after-184/apple-notes-vs-mudsnote.png`; the date, title, and body moved upward together without toolbar or pane regression.

## Decision

- Correct the remaining vertical delta at the shared safe-area origin instead of further compressing the already calibrated internal spacing.

## Next

- Continue Apple Notes parity from the packaged-app content comparison and extend installed smoke coverage to attachment rendering.
