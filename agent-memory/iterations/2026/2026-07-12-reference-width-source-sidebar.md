# 2026-07-12 reference-width source sidebar

## Request

Continue aligning Mudsnote with Apple Notes while preserving lightweight behavior and custom user layouts.

## Baseline

- Branch: `main`
- HEAD: `6def0f5`
- Worktree was clean.

## Changes

- Measured the expanded Apple Notes source pane at approximately `212pt`.
- Reduced source default/minimum width from `220pt` to `212pt`.
- Reduced inset source rows from `192pt` to `184pt`.
- Reduced consistent minimum window width from `904pt` to `896pt`.
- Added layout migration version 6 for exact prior `220/200pt` defaults.
- Preserved all customized source and note pane widths.

## Verification

- Focused migration and three-pane structure tests passed.
- Full `swift test` passed.
- `./scripts/package_app.sh` installed `/Applications/Mudsnote.app`.
- Strict code-sign verification passed.
- Expanded comparison: `/tmp/mudsnote-expanded-167/apple-notes-vs-mudsnote.png`.
- Collapsed comparison: `/tmp/mudsnote-collapsed-167/apple-notes-vs-mudsnote.png`.
- Expanded divider moved toward the reference without clipping rows or toolbar controls; collapsed geometry remained stable.

## Decisions

- Persisted custom geometry always takes precedence over a new visual default.

## Next

- Continue active toolbar and editor-content fidelity from state-matched captures.
