# 2026-07-12 reference-height editor title

## Request

Move the editor title higher to match the supplied clear Apple Notes crop.

## Baseline

- Branch: `main`
- HEAD: `223e880`
- Pre-existing iOS companion changes remained out of scope.

## Changes

- Replaced the privacy-blurred title-position assumption with the user's clear reference.
- Reduced date-to-title spacing from `34pt` to `8pt`.
- Kept date, toolbar, title font, body spacing, and horizontal reading edge unchanged.
- Updated the regression test to require a compact spacing smaller than the `20pt` date row.

## Verification

- Focused three-pane editor layout test passed.
- Full `swift test` passed after the final `8pt` value.
- `./scripts/package_app.sh` installed `/Applications/Mudsnote.app`.
- Strict code-sign verification passed.
- Content capture: `/tmp/mudsnote-content-168c/mudsnote-library.png`.
- Side-by-side comparison: `/tmp/mudsnote-content-168c/apple-notes-vs-mudsnote.png`.
- Mudsnote date/title tops measured approximately `147/205px`; the supplied clear reference measured approximately `143/211px` at the captured pixel scale.

## Decisions

- Use clear state-matched typography references for baseline decisions; blurred references are structural evidence only.

## Next

- Resume source-list vertical density tuning after this explicit title correction.
