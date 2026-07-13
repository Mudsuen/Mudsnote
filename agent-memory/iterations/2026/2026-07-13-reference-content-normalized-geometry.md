# 2026-07-13 Reference-content-normalized Notes geometry

## Scope

- Normalize the checked-in Apple Notes visual references to their real window-content bounds.
- Fix the resulting expanded, collapsed, toolbar, list-card, and editor-origin mismatches.
- Keep customized window and split widths intact during migration.

## Starting state

- Baseline HEAD during the macOS pass: `6ba38ca Add rendered attachment removal on iPhone`.
- Concurrent iOS work continued advancing `main` and modifying iOS files. Those files were excluded from this iteration.

## Changes

- `scripts/visual_notes_qa.sh` removes the built-in references' uniform `5pt` black margin, supports explicit custom insets, and writes source/normalized paths plus inset metadata.
- Canonical expanded geometry is `921x613pt` with `200/200pt` source/list columns. Layout migration version 8 recenters exact old default frames and replaces exact `205/200pt` pane defaults only.
- Collapsed list geometry now matches the normalized reference: selected card `20,204–345,339px` at `2x`, text beginning at `35pt`, and a bounded trailing inset that truncates long titles inside the card.
- Collapsed toolbar title, list stack, editor top/left origin, source padding, Add Folder wrapper, and Search wrapper were recalibrated from the same normalized origin.
- The content fixture selects `knock 短密码.md` so reference and app state are comparable.

## Verification

- `swift test` passed.
- Installed smoke passed at `/tmp/mudsnote-library-smoke-194-reference-origin`.
- `/Applications/Mudsnote.app` passed `codesign --verify --deep --strict`.
- Expanded visual evidence: `/tmp/mudsnote-visual-qa-194-empty-toolbar-fit-2/apple-notes-vs-mudsnote.png`.
- Collapsed visual evidence: `/tmp/mudsnote-visual-qa-194-collapsed-final/apple-notes-vs-mudsnote.png`.
- Content-state evidence: `/tmp/mudsnote-visual-qa-194-content-state-matched/apple-notes-vs-mudsnote.png`.

## Durable lesson

Reference screenshots may contain capture margins that are not part of the app window. Normalize source and current images to the same content origin before deriving geometry; otherwise every downstream constant can be consistently wrong while still appearing internally coherent.
