# 2026-07-10 native Markdown tables

## Request

Continue the Apple Notes parity goal while keeping Mudsnote lightweight. Replace the library editor's raw Markdown table presentation with a Notes-like editable grid, retain portable Markdown storage, and verify the real installed app. Exact color matching was not required.

## Baseline

- Branch: `main`
- HEAD: `129d6cb`
- Dirty files before work: `Sources/Mudsnote/MarkdownRichEditor.swift` contained the initial uncommitted native-table rendering pass from the active iteration.

## Changes

- Parsed valid Markdown table blocks and rendered them with `NSTextTable` and `NSTextTableBlock` cells instead of visible pipes and separator rows.
- Added stable table, row, column, column-count, placeholder, and terminal-newline metadata for editing and serialization.
- Preserved standard Markdown files through rich-grid serialization, including empty cells and table-adjacent/trailing newline behavior.
- Reworked Tab/Shift-Tab navigation, automatic final-row insertion, toolbar row insertion, Command-Delete row deletion, and context-menu row/column operations to use rich cell coordinates.
- Kept typing attributes inside empty and populated cells so edits do not break table structure.
- Added readable table preview text for note lists and search results, and bumped the disposable search-index cache schema to rebuild stale raw-pipe snippets.
- Updated the Apple Notes parity roadmap and changelog.

## Verification

- Commands run:
  - `swift test --filter MarkdownRichEditorTests`
  - `swift test`
  - `git diff --check`
  - `./scripts/package_app.sh`
  - `codesign --verify --deep --strict /Applications/Mudsnote.app`
- App/page/package actually opened:
  - `/Applications/Mudsnote.app`
  - isolated Table QA library rooted at `/tmp/mudsnote-table-qa-20260710`
- Result:
  - 111 tests passed across 2 suites.
  - The installed app rendered a two-column native grid with no visible Markdown pipes or separator syntax.
  - Real UI interaction changed `Active` to `Verified`, used three Tab presses to append a row, entered `New Row`, autosaved standard Markdown, and restored the same grid after relaunch.
  - The note-list preview changed from `| Name | Status |` to `Name  Status` after cache rebuild.
  - The isolated QA app was closed and the normal installed Mudsnote library was reopened.
- Not verified:
  - iOS was intentionally outside this macOS goal.

## Decisions

- Keep Markdown as the source of truth and use AppKit table objects only as the editor presentation layer.
- Use explicit attributed-string metadata for table interaction instead of reparsing visible editor text.
- Keep this iteration dependency-free and native rather than introducing a rich-document framework.

## Next

- Continue the highest-impact remaining Apple Notes gap, likely richer attachment previews or the next side-by-side shell delta.
