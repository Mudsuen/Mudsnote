# 2026-07-03 initial note loading shell

## Context

Continue the macOS Apple Notes parity goal after moving first-note loading off the main thread. iOS real-device validation remains out of scope.

Baseline before this slice: `fb47a1b Debounce library search typing`.

## Changes

- Added a launch-only loading shell for the initially selected note.
- The library now shows the selected note's list title and date immediately while the full Markdown body loads on a background queue.
- The editor is temporarily non-editable during that initial load, so users cannot modify a partially loaded document.
- Toolbar edit actions stay disabled while this initial loading shell is active.
- Regression coverage now checks that direct deferred show immediately presents the selected row's title before waiting for the Markdown title/body to load.

## Validation

- `swift test --filter MarkdownRichEditorTests/libraryWindowDeferredShowLoadsFirstNoteWithoutFocusingSearch`
- `swift test`
- `./scripts/package_app.sh`
- `/usr/bin/time -p ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-initial-loading-shell`

Packaged visual QA completed in 6.81s and captured:

- `mudsnote_window_bounds=x=360,y=66,width=1840,height=978`
- comparison image: `/tmp/mudsnote-visual-qa-initial-loading-shell/apple-notes-vs-mudsnote.png`

## Notes

- This keeps the Apple Notes-style shell responsive without pretending a slow cloud-backed Markdown body is already loaded.
- Full rich body loading still replaces the list-derived title with the Markdown document title once the file read completes.
