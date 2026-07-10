# 2026-07-10 note-list options toolbar

## Request

Continue Mudsnote toward Apple Notes UI and core-function parity while keeping the compact early toolbar baseline and preserving lightweight performance.

## Baseline

- Branch: `main`
- HEAD before work: `f4836c2 Relock compact Notes toolbar fade`
- Dirty files before work: none
- Visual baseline: `/tmp/mudsnote-visual-qa-pane-density-before-20260710/apple-notes-vs-mudsnote.png`

## Changes

- Added the missing middle-column ellipsis button beside New Note, separate from the editor/current-note more-actions button.
- Added a functional list-options menu with:
  - checked list view
  - optional date grouping
  - edited-date or title sorting
- Kept date groups in chronological order while title sorting applies within each group.
- Preserved search relevance order and current note selection when rebuilding list rows.
- Reduced the list-title toolbar wrapper from `248pt` to `208pt` so both middle-column actions fit without enlarging the note-list pane.
- Replaced the title/search-scope constraints with a horizontal stack so the hidden search scope collapses and `All iCloud` remains untruncated.
- Persisted sort and grouping preferences through the existing `NoteStore` settings domain.
- Kept sorting and grouping on the existing bounded in-memory snapshot; no new Markdown reads or index work were added.
- Made visual-QA note selection explicitly restore the requested row to the visible area and reset the top fixture to scroll origin zero.

## Verification

- Passed focused list-window and list-options tests (2 tests), including selection preservation and grouped title ordering.
- Passed full `swift test` (102 tests).
- Passed `git diff --check`.
- Passed `./scripts/package_app.sh`; installed `/Applications/Mudsnote.app`.
- Passed installed-app visual QA:
  - comparison: `/tmp/mudsnote-visual-qa-note-list-options-final2/apple-notes-vs-mudsnote.png`
  - original capture: `/tmp/mudsnote-visual-qa-note-list-options-final2/mudsnote-library.png`
  - window bounds: `1420x860`
  - `frontmost_before_capture=Mudsnote`
  - confirmed the full list title, list-options button, and New Note button stay inside the middle toolbar segment.
  - confirmed the requested `New Note` fixture remains visible at scroll origin zero with the Notes-like gold selection.

## Decisions

- The middle-column ellipsis owns list display, grouping, and sorting.
- The editor-side ellipsis continues to own actions for the selected note or notes.
- Search relevance outranks user-selected list ordering while a query is active.
- Visual-QA selection may normalize scroll position; normal library selection and user scrolling remain untouched.

## Next

- Continue with the next visible library-window delta without enlarging the compact toolbar or adding new list reads.
