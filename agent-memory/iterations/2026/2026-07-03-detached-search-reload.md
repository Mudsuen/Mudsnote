# 2026-07-03 detached search reload

## Context

Continue the macOS Apple Notes parity goal with emphasis on large-library search responsiveness. The previous iteration removed unrelated source-count refresh work from non-empty search reloads; the next gap was that actual result computation still happened on the main thread for ordinary typed searches.

Baseline before this slice: `179cbe0 Skip count refresh during library search`.

## Changes

- Added a cancellable detached search-result task for ordinary non-empty search typing and search-scope changes.
- Kept keyboard-command flushing synchronous so Return, Up, Down, and Escape still operate on fresh results immediately.
- Added generation checks so stale detached search results cannot overwrite newer queries, scopes, or all-notes/current-folder mode.
- Moved scoped search calculation into file-level helpers so detached tasks do not touch `NSWindowController` state off the main actor.
- Prevented deferred full-library snapshot completion from cancelling an active non-empty search result task.
- Updated the debounce test to wait for result state instead of assuming a fixed 220ms response under parallel test load.

## Validation

- `swift test --filter MarkdownRichEditorTests/librarySearchFieldDebouncesTypingButFlushesKeyboardActions`
- `swift test --filter 'MarkdownRichEditorTests/libraryWindowSearchScopesAndHighlightsMatches|MarkdownRichEditorTests/librarySearchFieldKeyboardNavigatesResultsAndClearsQuery|MarkdownRichEditorTests/librarySearchFieldDebouncesTypingButFlushesKeyboardActions'`
- `swift test`
- `./scripts/package_app.sh`
- `/usr/bin/time -p ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-detached-search-reload`

Packaged visual QA completed in 6.52s and captured:

- `mudsnote_window_bounds=x=36,y=69,width=1440,height=877`
- comparison image: `/tmp/mudsnote-visual-qa-detached-search-reload/apple-notes-vs-mudsnote.png`

## Notes

- A GCD-based first attempt crashed under Swift main-actor isolation because the closure still called controller instance methods off the main actor. The final implementation uses `Task.detached` and file-level helpers to keep background work away from AppKit/controller state.
