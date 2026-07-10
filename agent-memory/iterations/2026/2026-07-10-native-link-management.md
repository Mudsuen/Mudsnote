# 2026-07-10 native link management

## Request

Continue the active Mudsnote Apple Notes parity goal without reintroducing oversized windows or toolbar controls. Prioritize a missing everyday editing workflow while keeping the app lightweight and local-first.

## Baseline

- Branch: `main`
- HEAD: `be42dca`
- Dirty files before work: none.

## Changes

- Re-ran empty and content visual comparisons against `docs/visual-qa/apple-notes-reference.png` at the canonical window size.
- Preserved the current compact window and toolbar geometry because the comparison did not justify reversing the earlier user-approved size correction.
- Added attributed link references with label, URL, and effective text range.
- Added pointer feedback and pure Command-click opening for supported web, mail, and telephone links.
- Added native link menus in both library and floating editors: open, edit address, copy, and remove.
- Kept recently deleted notes read-only while still allowing link open and copy actions.
- Updated link URLs by editing semantic attributes, preserving visible labels and Markdown round-trip behavior; floating-editor changes use the existing formatting undo path.
- Changed note-list/search previews to remove link, emphasis, code, heading, checklist, and list Markdown syntax using shared precompiled regular expressions.
- Bumped the disposable search-index cache schema so older raw-Markdown previews rebuild.

## Verification

- Commands run:
  - `./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-20260710-next`
  - `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=content ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-20260710-content-next`
  - `swift test --filter MarkdownRichEditorTests.libraryAndFloatingEditorsManageMarkdownLinks`
  - `swift test --filter MudsnoteCoreTests.tableNotesUseReadableListPreviewText`
  - `swift test`
  - `git diff --check`
  - `./scripts/package_app.sh`
- App/page/package actually opened:
  - `/Applications/Mudsnote.app`
  - isolated link QA library rooted at `/tmp/mudsnote-link-qa-20260710`
- Result:
  - 112 tests passed across 2 suites.
  - The installed app displayed the four link actions in the native editor context menu.
  - Application-level action testing verified copied link text, URL updates, Markdown serialization, link removal, and floating-editor behavior.
  - Installed-app visual QA changed the list preview from `Visit [Muds](https://muds.top) for release notes.` to `Visit Muds for release notes.` while keeping the editor link styled and clickable.
  - The isolated QA instance was closed and the normal installed Mudsnote library was reopened.
- Not verified:
  - No external website was opened during automated smoke verification.
  - iOS remains outside the active macOS parity goal.

## Decisions

- Preserve current compact toolbar/window dimensions until a measured comparison shows a clear structural regression; do not tune dimensions from color differences.
- Treat rich links as attributed editor semantics over Markdown rather than introducing a new storage model.
- Use one shared lightweight preview transformation during indexing instead of rendering rich text for every note-list row.

## Next

- Continue the next highest-impact Apple Notes gap, likely richer inline attachment previews or another measured editor/list interaction delta.
