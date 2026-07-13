# 2026-07-13 iOS Markdown tables

## Request

Continue Notes-style iPhone editor parity with portable table creation and a
rendered-note-first reading experience.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `c6d4bc7`
- Concurrent macOS source and tests were preserved and excluded.

## Changes

- Added a table action to the existing single-row full-editor toolbar.
- The action inserts a portable two-column Markdown table at the current
  selection, keeps the table on its own lines, and positions the caret in the
  first body cell for immediate typing.
- Added deterministic GitHub-style table block parsing with alignment-marker
  support and strict column-count validation.
- Reading mode now renders tables as bordered, horizontally scrollable rows with
  a distinct header and alternating body treatment instead of exposing raw pipe
  syntax.
- Tables remain ordinary Markdown in storage and in the editor, preserving
  compatibility with the macOS app and other Markdown tools.
- UI fixtures and automation now prove a rendered table can coexist with a
  tappable Quick Look attachment in the same note.

## Verification

- Generic iOS Simulator SDK build passed at `/tmp/MudsnoteTableBuild`.
- Focused insertion/parser and full-editor UI checks passed (2 tests).
- Focused rendered-table plus Quick Look workflow passed.
- Full App and UI suite: 67 passed, 0 failed, 0 skipped.
- One iPhone 17 Pro / iOS 26.5 simulator was used with parallel testing disabled,
  then shut down; no iPad or additional simulator was used.
- Result bundles:
  - `/tmp/MudsnoteTableFocused.xcresult`
  - `/tmp/MudsnoteTableRenderedFocused.xcresult`
  - `/tmp/MudsnoteTableFullFinal.xcresult`

## Next

- Add document scanning and attachment rename/share actions, then continue into
  capture recovery, migration, and release-hardening work.
