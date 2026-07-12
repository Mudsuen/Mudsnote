# 2026-07-12 compact source-list rhythm

## Request

Continue matching Apple Notes after correcting the source-pane width and editor-title height.

## Baseline

- Branch: `main`
- HEAD: `c815428`
- Existing iOS companion changes remained out of scope.

## Changes

- Reduced source row height from `36pt` to `32pt`.
- Removed `1pt` inner row spacing and `6pt` uniform root-stack spacing.
- Added explicit `4pt` spacing after the iCloud heading.
- Preserved a deliberate `6pt` section break before Tags.
- Identified and tested the source root stack and its custom spacing.

## Verification

- Focused three-pane source-list structure test passed.
- Full `swift test` passed.
- `./scripts/package_app.sh` installed `/Applications/Mudsnote.app`.
- Strict code-sign verification passed.
- Expanded comparison: `/tmp/mudsnote-expanded-169/apple-notes-vs-mudsnote.png`.
- Visual inspection confirmed `32–33pt` row-center rhythm, complete long labels/counts, and an unclipped selected background.

## Decisions

- Use zero-gap rows as the density baseline and add only semantic group spacing explicitly.

## Next

- Continue toolbar active-state and editor rich-content fidelity from clear references.
