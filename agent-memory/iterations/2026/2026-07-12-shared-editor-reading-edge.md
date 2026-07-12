# 2026-07-12 shared editor reading edge

## Request

Continue aligning the macOS editor with Apple Notes while preserving a lightweight, performant architecture.

## Baseline

- Branch: `main`
- HEAD: `c96386a`
- Worktree was clean.

## Changes

- Captured the content fixture against the checked-in Apple Notes content reference.
- Separated the editor's outer stack inset from TextKit's internal padding during measurement.
- Reduced the outer horizontal inset from `24pt` to `22pt`.
- Reduced horizontal text-container padding from `4pt` to `2pt`.
- Preserved the reference-calibrated `18pt` top inset and `34pt` date-to-title spacing.

## Verification

- Focused three-pane editor structure test passed.
- Full `swift test` passed.
- `./scripts/package_app.sh` installed `/Applications/Mudsnote.app`.
- Strict code-sign verification passed.
- Content comparison: `/tmp/mudsnote-content-166b/apple-notes-vs-mudsnote.png`.
- Visual inspection confirmed aligned title/body reading edges without clipping or divider crowding.

## Decisions

- Treat AppKit/TextKit internal padding as part of visible alignment measurements.

## Next

- Improve active-window capture stability, then continue toolbar and rich-content parity from state-matched evidence.
