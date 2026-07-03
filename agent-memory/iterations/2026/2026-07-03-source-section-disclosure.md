# 2026-07-03 Source Section Disclosure

## Request

Continue the active macOS Apple Notes parity goal for Mudsnote while keeping the app lightweight and local-first.

## Baseline

- Branch: `main`
- HEAD: `8d37db4`
- Dirty files before work: none

## Changes

- Replaced the static `文件夹` and `标签` source-list section labels with lightweight AppKit disclosure buttons.
- Added session-local collapsed state for folder and tag sections.
- Collapsing a section hides its rows without clearing the selected scope or rescanning the library.
- Expanding folders/tags reuses the existing deferred-load paths.
- Added `sourceCountSnapshot` so section disclosure can refresh visible counts from the last known source-count snapshot instead of synchronously scanning up to 10,000 notes.
- Extended `scripts/visual_notes_qa.sh` metadata with captured Mudsnote `CGWindow` id and bounds.

## Verification

- Focused tests passed:
  - `swift test --filter MarkdownRichEditorTests/libraryWindowLoadsTagRowsAfterShellIsVisible`
  - `swift test --filter MarkdownRichEditorTests/libraryWindowShowsNestedFoldersInSourceList`
- `swift test` passed with 86 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- `bash -n scripts/visual_notes_qa.sh` passed.
- `./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-source-section-collapse` passed.
- Visual QA metadata confirmed:
  - Mudsnote window bounds: `x=305,y=241,width=1840,height=978`
  - Mudsnote screenshot: `1952x1090 pt`, `3904x2180 px`, `2.0x`

## Decisions

- Keep section collapse as session-local UI state. It improves Notes-like sidebar hierarchy without introducing persisted sidebar preferences yet.
- Use the last source-count snapshot for disclosure-only redraws to keep the interaction lightweight.

## Next

- Continue source-list hierarchy tuning: account-level top rows, section spacing, and icon contrast.
- Continue toolbar spacing and editor visual rhythm against the point-normalized visual QA.
