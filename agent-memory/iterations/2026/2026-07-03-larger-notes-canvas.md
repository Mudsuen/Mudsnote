# 2026-07-03 Larger Notes Canvas

## Context

The persistent-index iteration kept the main window functional, but visual QA still made Mudsnote look smaller and more utility-like than the Apple Notes reference. The source list, note list, and toolbar search field were also narrower than the target desktop workspace.

## Change

- Increased the library's initial window size to `1720x940`.
- Increased the presented target size to `1840x1010`.
- Kept screen clamping through `LibraryNotesLayout.presentedWindowSize(in:)`.
- Widened the source column to `320`.
- Widened the note list column to `390`.
- Widened the note table and toolbar search field to keep the larger canvas coherent.

## Verification

- Focused layout tests passed for the Notes-like split window, toolbar disabled states, and note-scroll width contract.
- `swift test` passed.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged-app direct launch smoke opened `Mudsnote 笔记` at `1840x978` on the current screen after clamping.
- Visual QA generated `/tmp/mudsnote-visual-qa-larger-notes-canvas/apple-notes-vs-mudsnote.png`.

## Follow-up

- Continue visual tuning on source hierarchy, note-list drag previews, and editor text scale once the larger canvas is verified.
