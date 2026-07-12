# 2026-07-12 reference-width toolbar search

## Request

Continue matching Apple Notes toolbar proportions while keeping search behavior lightweight and native.

## Baseline

- Branch: `main`
- HEAD: `964e480`
- Existing iOS companion changes remained out of scope.

## Changes

- Reduced toolbar search width from `210pt` to `160pt`.
- Reduced its wrapper width from `230pt` to `180pt`.
- Preserved field/wrapper heights at `32/36pt`.
- Kept search scope, focus, keyboard navigation, and query execution unchanged.

## Verification

- Focused three-pane/toolbar test passed.
- Full `swift test` passed.
- `./scripts/package_app.sh` installed `/Applications/Mudsnote.app`.
- Strict code-sign verification passed.
- Expanded comparison: `/tmp/mudsnote-search-172/apple-notes-vs-mudsnote.png`.
- Collapsed full-window capture: `/tmp/mudsnote-search-collapsed-172/mudsnote-capture-source.png`.
- Search label/icon and neighboring tools remain unclipped in both states.

## Decisions

- Match native search width independently from its established height and behavior.

## Next

- Continue per-symbol and rich-editor fidelity from clear references.
