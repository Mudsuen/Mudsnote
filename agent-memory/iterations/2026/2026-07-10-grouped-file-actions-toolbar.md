# 2026-07-10 grouped file-actions toolbar

## Request

Continue Mudsnote toward Apple Notes UI parity while preserving the earlier compact, no-visible-rim toolbar baseline and lightweight performance.

## Baseline

- Branch: `main`
- HEAD before work: `cb95459 Add Notes list display controls`
- Dirty files before work: none
- Visual baseline: `/tmp/mudsnote-visual-qa-file-actions-before-20260710/apple-notes-vs-mudsnote.png`

## Changes

- Replaced the two top-level share/export and more toolbar items with one `file-actions` item.
- Hosted the existing independent menu buttons inside a compact `72x32` dark capsule.
- Kept both child buttons at the locked `30x28` size with native symbols, existing menus, accessibility labels, and icon-level disabled tinting.
- Kept the capsule border width and border alpha at zero so grouping does not reintroduce the bright rim the user rejected.
- Reused the existing in-memory toolbar state update path; no file reads, indexing, or note loading were added.

## Verification

- Passed focused library-window and toolbar-state tests (2 tests).
- Passed full `swift test` (102 tests).
- Passed `git diff --check`.
- Passed `./scripts/package_app.sh`; installed `/Applications/Mudsnote.app`.
- Passed final installed-app visual QA:
  - comparison: `/tmp/mudsnote-visual-qa-file-actions-final2/apple-notes-vs-mudsnote.png`
  - window bounds: `1420x860`
  - `frontmost_before_capture=Mudsnote`
  - confirmed grouped file actions remain compact, borderless, and do not squeeze search.
  - confirmed the isolated `New Note` fixture remains visible and selected.

## Decisions

- Keep share/export and more as separate actions inside one visual group.
- Do not use `NSMenuToolbarItem` or system menu chrome for this group because it reintroduces heavier borders.
- Do not enlarge the existing editor-tools capsule, search field, or window to make room.
- Visual-QA-only selection pinning keeps automated captures deterministic after background snapshot reloads; it does not constrain normal user scrolling.

## Next

- Complete verification, then continue with the next visible Apple Notes toolbar or source-list delta.
