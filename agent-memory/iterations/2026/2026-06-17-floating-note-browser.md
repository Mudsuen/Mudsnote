# 2026-06-17 floating note browser

## Request

Make the Mudsnote floating note support selecting among multiple notes through a Raycast Notes-like popup opened from the top-right search/browse control. Keep only one top-right button: browse notes.

## Baseline

- Branch: main
- HEAD: 3c521c5
- Dirty files before work: existing iOS companion and `.gitignore` changes were present and not touched.

## Changes

- Replaced the floating note header actions with a single `浏览笔记` button.
- Added a compact floating note browser popup with a search field, Notes header, count, and up to five note rows.
- Selecting a result loads that Markdown file into the existing floating note window instead of opening a separate editor.
- Added `activeFloatingNoteURL` so the floating note keeps its window mode while editing an existing file.
- Updated floating-note save and draft metadata so saving a selected note updates the existing file.
- Added app tests for the one-button header and switching/saving an existing note.

## Verification

- Commands run:
  - `swift test`
  - `./scripts/package_app.sh`
  - `open -n /Applications/Mudsnote.app --args --floating-note`
- App/page/package actually opened: `/Applications/Mudsnote.app`
- Result: 54 tests passed, package installed successfully, packaged floating-note smoke opened.
- Not verified: manual click-through of the hover-revealed browse popup in the live app.

## Decisions

- The global search window remains unchanged.
- In floating-note mode, `Cmd+F` and the browse button now open the floating note browser so note switching stays in the same floating window.

## Next

- If needed, manually inspect hover/click behavior of the browse button and tune popup placement against the live window.
