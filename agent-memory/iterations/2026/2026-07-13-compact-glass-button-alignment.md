# 2026-07-13 compact glass button alignment

## Request

Continue Apple Notes UI parity with native macOS button material, sizing, hover behavior, and lightweight architecture.

## Baseline

- Branch: `main`
- HEAD: `1e2937d`
- Dirty files before work: none

## Changes

- Added a `44pt` New Note toolbar layout slot while keeping the native glass button at `30pt`.
- Trailing alignment moves the button and editor-tools cluster away from the editor divider without changing the search field or pane widths.
- Added a compact `12pt` SF Symbol configuration for New Note and the collapsed Sidebar Toggle.
- Kept `.scaleNone` only for compact glass symbols so AppKit does not shrink them into the glass bezel's small content rect.

## Verification

- Focused toolbar structure, disabled-state, and note-lifecycle tests passed.
- Expanded comparison: `/tmp/mudsnote-visual-qa-200-final-expanded/apple-notes-vs-mudsnote.png`.
- Collapsed comparison: `/tmp/mudsnote-visual-qa-200-final-collapsed/apple-notes-vs-mudsnote.png`.
- Full `swift test` passed.
- `/Applications/Mudsnote.app` was repackaged and `scripts/library_smoke.sh` passed.
- `codesign --verify --deep --strict /Applications/Mudsnote.app` passed.

## Decisions

- Preserve native AppKit glass and toolbar drawing; custom layout slots may position native controls but must not replace their interaction rendering.
- Size compact SF Symbols from their resulting `NSImage` canvas rather than assuming the requested point size equals visible bounds.

## Next

- Continue with deeper per-symbol toolbar tuning or complex editor-content parity based on the next same-state visual audit.
