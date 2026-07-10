# 2026-07-11 sidebar disclosure persistence

## Request

Continue the Apple Notes parity goal with measured UI changes, preserving the compact no-rim toolbar baseline and lightweight performance.

## Baseline

- Branch: `main`
- HEAD: `715b112`
- Dirty files before work: none.
- User content-state reference: `/var/folders/hs/3lbg6xjs1kdc4xftnflt94y80000gn/T/codex-clipboard-hBV7X2.png`.

## Changes

- Re-ran content-state visual QA against the user's Apple Notes screenshot instead of the empty-note reference.
- Preserved window, toolbar, editor typography, and list-row geometry because the content comparison did not justify reversing the approved compact baseline.
- Removed a hard-coded weekday from the content fixture so list metadata no longer duplicates or conflicts with the generated modification weekday.
- Persisted expanded and collapsed folder paths plus Folders and Tags section disclosure state in `UserDefaults`.
- Restored disclosure state before source-list construction, so the first visible hierarchy matches the previous session.
- Remapped stored disclosure paths when folders are renamed and removed stale descendants when folders are deleted.
- Reused existing source-list rebuilds and deferred folder/tag loading; no note parsing, indexing, or filesystem scan was added to persistence.

## Verification

- Commands run:
  - `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=content MUDSNOTE_NOTES_REFERENCE=.../codex-clipboard-hBV7X2.png ./scripts/visual_notes_qa.sh /tmp/mudsnote-content-reference-20260711`
  - `swift test --filter folderDisclosurePathsPersistAndFollowFolderLifecycle`
  - `swift test --filter libraryWindowShowsNestedFoldersInSourceList`
  - `swift test --filter libraryWindowLoadsTagRowsAfterShellIsVisible`
  - `swift test`
  - `git diff --check`
  - `./scripts/package_app.sh`
  - `codesign --verify --deep --strict /Applications/Mudsnote.app`
- Result:
  - Final full test run passed: 115 tests across 2 suites.
  - Installed-app QA expanded `Projects` to reveal `Client`, collapsed `Tags`, terminated Mudsnote, and relaunched the same isolated library.
  - The new process immediately restored the visible `Client` row while keeping the `library` tag row hidden.
  - Defaults contained only the expanded folder path and Tags collapsed Boolean; no note data or index cache was used for UI state.
  - Restart evidence: `/tmp/mudsnote-disclosure-qa-20260711/restarted.png`.
  - Strict code-signature verification passed.
- Not verified:
  - iOS remains outside the active macOS parity goal.

## Decisions

- Keep disclosure persistence independent from search/index state.
- Store standardized paths and follow folder lifecycle changes to avoid stale preferences.
- Do not resize the toolbar or window from this comparison; the user-approved compact baseline remains fixed.

## Next

- Continue the next measured toolbar-symbol or source-list hierarchy delta without enlarging controls.
