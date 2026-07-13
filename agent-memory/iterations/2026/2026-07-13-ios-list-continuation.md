# 2026-07-13 iOS list continuation

## Request

Continue the Notes-style iPhone editor with native-feeling list creation and
keyboard behavior while preserving Markdown as the storage format.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `cb4d01b`
- Concurrent macOS, core-test, and script changes were preserved and excluded.

## Changes

- Added an ordered-list control to the single-row horizontal editor toolbar.
- Added a rendered bullet marker that conceals only the Markdown bullet syntax in
  Rich Text mode while preserving the exact source string.
- Return continues bullets with the same marker and indentation.
- Return increments ordered-list numbers while retaining indentation and the
  original `.` or `)` delimiter.
- Return after a checklist item creates a new unchecked checklist item.
- Return on an empty bullet, ordered item, or checklist exits the list.
- Delete at the beginning of list content removes the complete Markdown prefix in
  one action instead of exposing or deleting one concealed character.
- Markdown Source mode retains normal literal keyboard editing behavior.
- All transformations use explicit UTF-16 ranges and return the intended cursor
  position, making them deterministic and directly testable.

## Verification

- Generic iOS Simulator SDK build passed.
- Four focused list presentation and keyboard-semantic tests passed.
- Full App and UI suite: 61 passed, 0 failed, 0 skipped.
- One iPhone 17 Pro / iOS 26.5 simulator was explicitly booted, used with parallel
  testing disabled, and shut down afterward.
- Result bundles:
  - `/tmp/MudsnoteListEditingFocused.xcresult`
  - `/tmp/MudsnoteListEditingFull.xcresult`

## Next

- Add Notes-style Tab/Shift-Tab indentation for nested lists, then continue editor
  parity with tables, scan/document attachments, and richer inline media handling.
