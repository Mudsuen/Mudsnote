# 2026-07-03 search debounce and launch hydration

## Context

Continue the active macOS Apple Notes parity goal for Mudsnote. iOS real-device validation is explicitly out of scope for this goal.

Baseline before this slice: `221b82a Add collapsible source sections`.

## Changes

- Debounced toolbar search typing so every character does not synchronously rebuild the note list.
- Flushed any pending debounced search immediately for search-field keyboard commands, preserving Return, Up, Down, and Escape behavior.
- Cancelled pending search reload work on scope changes, programmatic search, clear, and window close.
- Changed first-note launch hydration to select the first visible row without firing the selection delegate and load that note on a background queue.
- Added a main-thread stale-selection guard before applying the asynchronously loaded first note, so later user navigation is not overwritten.

## Validation

- `swift test --filter MarkdownRichEditorTests/libraryWindowDeferredShowLoadsFirstNoteWithoutFocusingSearch`
- `swift test`
- `./scripts/package_app.sh`
- `/usr/bin/time -p ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-search-debounce-async`

Packaged visual QA completed in 7.09s and captured the installed app window:

- `mudsnote_window_bounds=x=360,y=66,width=1840,height=978`
- comparison image: `/tmp/mudsnote-visual-qa-search-debounce-async/apple-notes-vs-mudsnote.png`

## Notes

- A pre-fix packaged smoke run exposed the real issue: the Mudsnote process was frontmost while the main thread was blocked in `LibraryWindowController.loadInitialNoteAfterLaunch` -> `NoteStore.loadNote` -> `String(contentsOf:)` -> `open`.
- Moving the first-note file read off the main thread preserves direct launch responsiveness even when a Markdown file or cloud-backed path is slow to open.
- The editor can briefly show its empty/loading state while the selected note body is still being read; the three-pane Notes-like shell remains responsive.
