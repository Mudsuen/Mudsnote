# 2026-07-02 Wider library default

## Context

The first repeatable side-by-side visual QA artifact showed the Mudsnote library window was narrower than the Apple Notes reference. The editor pane was visibly compressed even after source-list density and editor rhythm improvements.

## Change

- Increased the library window creation width from 1040 to 1160.
- Increased the direct-open centered target size from 1040x764 to 1160x764.
- Kept source list and note list fixed widths unchanged so the added space goes to the editor pane.

## Verification

- `swift test` passed with 77 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- `./scripts/visual_notes_qa.sh` generated `/tmp/mudsnote-visual-qa/apple-notes-vs-mudsnote.png`.
- Visual QA confirmed a wider Notes-like window with the first note loaded and no focused search field.
