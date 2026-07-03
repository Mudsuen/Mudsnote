# 2026-07-03 Editor Search Highlights

## Request

Continue the active Apple Notes parity goal for Mudsnote while keeping the app lightweight and local-first. iOS real-device validation is not part of this macOS Notes-parity goal.

## Baseline

- Branch: `main`
- HEAD: `e1afee0`
- Dirty files before work: none

## Changes

- Added a private `.qmSearchHighlight` attributed-string marker for editor search highlights.
- Reused the active library search query to highlight matches inside the loaded editor body.
- Clears editor search highlights when search is cleared.
- Suppresses search-highlight attribute changes from normal editor dirty/autosave handling.
- Keeps Markdown serialization unchanged because highlights are visual attributes only.

## Verification

- Focused search tests passed:
  - `swift test --filter 'libraryWindowSearchScopesAndHighlightsMatches|librarySearchFieldKeyboardNavigatesResultsAndClearsQuery'`
- `swift test` passed.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged-app direct launch smoke opened `Mudsnote 笔记` at `1840x978`.
- Visual QA generated `/tmp/mudsnote-visual-qa-editor-search-highlights/apple-notes-vs-mudsnote.png`.

## Decisions

- Search highlighting remains disposable UI state, not persisted note metadata.

## Next

- Improve large-library search/loading state.
- Continue editor visual tuning and richer attachment previews.
