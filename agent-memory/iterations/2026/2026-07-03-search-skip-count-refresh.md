# 2026-07-03 search skip count refresh

## Context

Continue the macOS Apple Notes parity goal with emphasis on large-library responsiveness. After search typing was debounced, a non-empty search reload still computed the full all-notes snapshot before executing the actual search, mostly to refresh source-list counts that are unrelated to the active query.

Baseline before this slice: `15b295c Expand library toolbar chrome`.

## Changes

- Made library reloads lazily compute the all-notes snapshot only when the current query is empty or source counts actually need refreshing.
- Changed debounced search typing reloads to skip source-count refreshes for non-empty queries.
- Changed search scope toggles to skip unrelated source-count refreshes.
- Changed programmatic library search to refresh counts only when clearing back to an empty query.

## Validation

- `swift test --filter 'MarkdownRichEditorTests/libraryWindowSearchScopesAndHighlightsMatches|MarkdownRichEditorTests/librarySearchFieldKeyboardNavigatesResultsAndClearsQuery|MarkdownRichEditorTests/librarySearchFieldDebouncesTypingButFlushesKeyboardActions'`
- `swift test`
- `./scripts/package_app.sh`
- `/usr/bin/time -p ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-search-skip-count-refresh`

Packaged visual QA completed in 6.72s and captured:

- `mudsnote_window_bounds=x=36,y=69,width=1440,height=877`
- comparison image: `/tmp/mudsnote-visual-qa-search-skip-count-refresh/apple-notes-vs-mudsnote.png`

## Notes

- The search result path still uses the existing Markdown index and ranking behavior.
- This does not implement full cancellable background search yet; it removes one avoidable full-library step from the hot search-input path.
