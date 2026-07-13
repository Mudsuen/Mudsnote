# 2026-07-13 Collapsed toolbar title gap

## Request

Continue Apple Notes UI alignment after the reference-content normalization pass.

## Baseline

- Branch: `main`
- HEAD: `91b0754`
- Dirty files before work: none

## Changes

- Measured `All iCloud` with Vision OCR in the normalized collapsed reference and current installed capture.
- Changed the source-hidden toolbar title offset from `-16pt` to `-11.5pt`, moving the title about `4.5pt` right without affecting the sidebar button or content panes. The `-11pt` and `-12pt` probes landed `2.2px` right and `1.7px` left of the reference, so the final value uses the Retina half-point between them.
- Updated the toolbar-state regression and current handoff values.

## Verification

- Commands run: focused toolbar regression, full `swift test`, `./scripts/package_app.sh`, `./scripts/library_smoke.sh /tmp/mudsnote-library-smoke-195-collapsed-title`, normalized collapsed visual QA, Vision OCR, and `codesign --verify --deep --strict /Applications/Mudsnote.app`.
- App/page/package actually opened: `/Applications/Mudsnote.app` in the isolated collapsed fixture and installed smoke fixture.
- Result: Apple Notes `All iCloud` begins at `x=309.7px`; final Mudsnote begins at `x=309.9px` at `2x`. Full tests, installed smoke, packaging, and signature verification passed.
- Visual evidence: `/tmp/mudsnote-visual-qa-195-collapsed-title-halfpoint/apple-notes-vs-mudsnote.png`.
- Not verified: iOS real-device validation remains outside the active goal.

## Decisions

- Calibrate the collapsed title independently from the content-origin correction because its local toolbar-item spacing is separate from pane geometry.

## Next

- Continue with the next largest non-intentional difference in the normalized three-state visual evidence.
