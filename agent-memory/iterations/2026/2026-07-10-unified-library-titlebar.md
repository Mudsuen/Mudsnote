# Unified Library Titlebar

## Scope

- Baseline: `b160a71 Fix window-only Notes visual capture`
- Restore the earlier Apple Notes-like single-row titlebar while retaining all later toolbar controls and styling.

## Evidence

- The corrected window-only crop shows Mudsnote traffic lights on a separate upper row while Apple Notes keeps traffic lights and toolbar controls in one row.
- Repository history identifies `15b295c Expand library toolbar chrome` as the change from `.unified` to `.expanded`.
- The user explicitly identified the earlier toolbar version as visually closer.

## Implementation

- Restored `NSWindow.ToolbarStyle.unified` for the library window.
- Preserved transparent titlebar behavior, hidden title, tracking separators, compact circular actions, editor-tools capsule, file-actions capsule, and search field.

## Verification

- Targeted main-layout/toolbar test passed.
- Full `swift test` passed: 103 tests in 2 suites.
- `git diff --check` passed.
- `./scripts/package_app.sh` installed the unified-titlebar build at `/Applications/Mudsnote.app`.
- Live window-only visual QA remains pending because the current desktop session exposes no frontmost application; the corrected harness exits safely and removes the isolated QA process.
