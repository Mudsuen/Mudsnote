# 2026-07-13 iOS nested list indentation

## Request

Continue Notes-style iPhone editor parity after list continuation by adding direct
nested-list controls without introducing a second toolbar row.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `28490c0`
- Concurrent macOS, documentation, core-test, script, and iteration-record changes
  were preserved and excluded.

## Changes

- Added decrease-indent and increase-indent controls to the existing single-row,
  horizontally scrolling editor toolbar.
- Indentation changes only selected bullet, ordered, and checklist lines; ordinary
  body paragraphs remain untouched.
- Increase indent adds one deterministic two-space Markdown nesting level.
- Decrease indent removes one two-space level, one space, or one tab, and becomes a
  no-op for an already-root-level list.
- Multi-line selection boundaries avoid pulling in an unselected following line
  when the selection ends on a newline.
- The resulting selection remains over the transformed list block so repeated
  nesting operations are predictable.
- Nested items reuse the existing rendered markers and Return/Delete continuation
  behavior while retaining exact Markdown source.

## Verification

- Generic iOS Simulator SDK build passed.
- Focused nested-list transformation test passed.
- Full App and UI suite: 62 passed, 0 failed, 0 skipped.
- One iPhone 17 Pro / iOS 26.5 simulator was explicitly booted, used with parallel
  testing disabled, and shut down afterward.
- Result bundles:
  - `/tmp/MudsnoteListIndentFocused.xcresult`
  - `/tmp/MudsnoteListIndentFull.xcresult`

## Next

- Continue editor parity with Notes-style inline tables and document scanning/file
  attachments, then close the remaining search and quick-capture behavior gaps.
