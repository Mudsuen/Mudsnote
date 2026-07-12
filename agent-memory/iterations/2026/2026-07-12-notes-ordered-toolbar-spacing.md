# 2026-07-12 Notes-ordered toolbar spacing

## Request

Continue matching Apple Notes toolbar composition without restoring unnecessary share or ellipsis commands.

## Baseline

- Branch: `main`
- HEAD: `bcc3b86`
- Existing iOS companion changes remained out of scope.

## Changes

- Moved flexible space from between New Note and editor tools to between editor tools and Search.
- Added one native fixed space between New Note and editor tools.
- Added an exact regression test for the default toolbar suffix order.
- Kept share, ellipsis, and standalone duplicate editor-tool items absent.

## Verification

- Focused toolbar/three-pane structure test passed after correcting the test to use public identifier values.
- Full `swift test` passed.
- `./scripts/package_app.sh` installed `/Applications/Mudsnote.app`.
- Strict code-sign verification passed.
- Expanded comparison: `/tmp/mudsnote-toolbar-171/apple-notes-vs-mudsnote.png`.
- Collapsed full-window capture: `/tmp/mudsnote-toolbar-collapsed-171/mudsnote-capture-source.png`.
- New Note-to-tools gap measured approximately `19.5pt`, close to the reference's `18.5pt`; collapsed title and toolbar remain unclipped.

## Decisions

- Use fixed toolbar space inside a command cluster and flexible space only between clusters.

## Next

- Continue per-symbol and rich-editor fidelity from clear references.
