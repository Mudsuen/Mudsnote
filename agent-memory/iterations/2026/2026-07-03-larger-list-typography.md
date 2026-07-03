# 2026-07-03 Larger List Typography

## Context

After increasing the Notes-like library canvas, visual QA showed the source list and note list still reading smaller than Apple Notes. The main surface was closer in size, but the row hierarchy still felt compressed.

## Change

- Increased source row height from `30` to `34`.
- Increased source group, source button, and source count font sizes.
- Increased note group row height from `56` to `62`.
- Increased note row height from `72` to `86`.
- Increased note title, snippet, and metadata font sizes.
- Added note-list header title/count font constants and increased their sizes.
- Slightly increased note-cell top, leading, and bottom padding.

## Verification

- Focused layout tests passed for the Notes-like split window, nested source folders, and toolbar disabled-state surface.
- `swift test` passed.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged-app direct launch smoke opened `Mudsnote 笔记` at `1840x978`.
- Visual QA generated `/tmp/mudsnote-visual-qa-larger-list-typography/apple-notes-vs-mudsnote.png`.

## Follow-up

- Continue source-list hierarchy visual tuning.
- Add richer drag preview/count visuals for multi-note dragging.
- Tune editor text scale after list density settles.
