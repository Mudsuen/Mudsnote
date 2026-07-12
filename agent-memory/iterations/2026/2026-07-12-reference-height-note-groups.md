# 2026-07-12 reference-height note groups

## Request

Continue matching Apple Notes list geometry after source-sidebar and editor-title corrections.

## Baseline

- Branch: `main`
- HEAD: `a2fddbb`
- Worktree was clean.

## Changes

- Reduced note-group rows from `54pt` to `45pt`.
- Increased group-title bottom inset from `12pt` to `15pt`.
- Kept note rows, selection geometry, list insets, and scrollbar behavior unchanged.

## Verification

- Focused three-pane list structure test passed.
- `./scripts/package_app.sh` installed `/Applications/Mudsnote.app`.
- Strict code-sign verification passed.
- Collapsed comparison: `/tmp/mudsnote-collapsed-170/apple-notes-vs-mudsnote.png`.
- Expanded comparison: `/tmp/mudsnote-expanded-170/apple-notes-vs-mudsnote.png`.
- Both comparisons align group-heading and first-card top coordinates with their state-matched references.
- Initial full test run had two asynchronous background-refresh timing failures; both passed together on focused rerun.
- A subsequent full run passed all `143` tests in both suites.

## Decisions

- Tune group-row height and title inset independently because they govern different visible coordinates.

## Next

- Continue toolbar active-state and rich-editor fidelity from clear references.
