# 2026-07-13 Editor date center

## Request

Continue Apple Notes visual alignment after fixing the editor date baseline.

## Baseline

- Branch: `main`
- HEAD: `6f36bd5`
- Dirty files before work: concurrent iOS reader/app/UI-test changes; excluded from this macOS pass.

## Changes

- Measured the normalized Apple Notes date center at about `x=1311.9px` in empty and content states.
- Measured Mudsnote around `x=1328–1329px` because the date label used the full editor-pane center.
- Added a `-8.5pt` status-label center offset without changing date vertical position, title/body content, or pane geometry.
- Added a constraint-level regression for the independent status offset.

## Verification

- Focused constraint regression and full `swift test` passed.
- `./scripts/package_app.sh` installed `/Applications/Mudsnote.app`; strict deep signature verification passed.
- Installed smoke passed at `/tmp/mudsnote-library-smoke-198-editor-date-center`, including save, trash/restore, folder move, attachment copy, and attachment reload.
- Empty state: Apple Notes and Mudsnote date centers both measure `x=1311.9px`; both retain `y=123.0px`.
- Content state: Apple Notes center is `x=1311.9px`; Mudsnote is `x=1310.6px`, a `1.3px` OCR difference; both retain `y=123.0px`.
- Collapsed editor title remains Apple Notes `y=186px`, Mudsnote `y=184px`.
- Empty evidence: `/tmp/mudsnote-visual-qa-198-empty-center/apple-notes-vs-mudsnote.png`.
- Content evidence: `/tmp/mudsnote-visual-qa-198-content-center/apple-notes-vs-mudsnote.png`.
- Collapsed evidence: `/tmp/mudsnote-visual-qa-198-collapsed-regression/apple-notes-vs-mudsnote.png`.

## Decisions

- Date-row centering is independent of editor content insets because the reference visually centers against the unobstructed scrolling region.

## Next

- Continue with the next largest non-intentional mismatch in the normalized visual evidence.
