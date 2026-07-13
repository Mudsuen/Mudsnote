# 2026-07-13 Expanded toolbar title origin

## Request

Continue macOS Apple Notes visual alignment without changing intentionally omitted features.

## Baseline

- Branch: `main`
- HEAD: `255e8d5`
- Dirty files before work: concurrent iOS search changes and their iteration record; excluded from this macOS pass.

## Changes

- Measured normalized expanded captures with Vision OCR.
- Added a `12pt` source-visible title offset while retaining the independently measured `-11.5pt` source-hidden offset.
- Extended the toolbar transition regression to verify both state-specific values.

## Verification

- Focused toolbar-state regression and full `swift test` passed.
- `./scripts/package_app.sh` installed `/Applications/Mudsnote.app` and signing verification passed.
- Installed smoke passed at `/tmp/mudsnote-library-smoke-196-expanded-title`, including save, trash/restore, folder move, attachment copy, and attachment reload.
- Expanded OCR: Apple Notes `x=455.0px`; Mudsnote `x=454.9px`.
- Collapsed regression OCR: Apple Notes `x=309.7px`; Mudsnote `x=309.9px`.
- Expanded evidence: `/tmp/mudsnote-visual-qa-196-expanded-title/apple-notes-vs-mudsnote.png`.
- Collapsed evidence: `/tmp/mudsnote-visual-qa-196-collapsed-regression/apple-notes-vs-mudsnote.png`.

## Decisions

- Expanded and collapsed toolbar title origins are independent because AppKit reflows neighboring toolbar items when the source sidebar controls hide.

## Next

- Continue with the next largest non-intentional mismatch in the normalized expanded/content evidence.
