# 2026-07-13 iOS direct checklist editing

## Request

Continue Notes-style direct interaction in the rendered iPhone Markdown editor.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `b1076f0`
- Concurrent macOS, core-test, and script changes were preserved and excluded.

## Changes

- Detects Markdown checklist prefixes while retaining the exact source string.
- Conceals `- [ ]` and `- [x]` in Rich Text mode and draws native circle/checkmark
  controls at the same text-layout position.
- Tapping a drawn control directly toggles only the Markdown state character between
  a space and `x`.
- The checklist tap recognizer does not cancel normal text touches, so cursor
  placement and selection continue to work.
- Markdown Source mode removes the drawn controls and shows the original markers.
- Checklist edits flow through the existing binding, debounced autosave, conflict
  detection, and list metadata refresh.

## Verification

- Generic iOS Simulator SDK build passed.
- Focused presentation test passed for open/checked detection, exact source toggle,
  and source-mode restoration.
- Full App and UI suite: 58 passed, 0 failed, 0 skipped.
- One iPhone 17 Pro / iOS 26.5 simulator was explicitly booted, used with parallel
  testing disabled, and shut down afterward.
- Result bundles:
  - `/tmp/MudsnoteChecklistFocused.xcresult`
  - `/tmp/MudsnoteChecklistFull.xcresult`

## Next

- Render bullets and ordered-list indentation directly, then improve Return/Delete
  continuation behavior for list and checklist paragraphs.
