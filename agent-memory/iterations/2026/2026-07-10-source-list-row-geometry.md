# Source List Row Geometry

## Scope

- Baseline: `8e071e8 Align Notes list row geometry`
- Keep source actions, menus, counts, folder disclosure, drag and drop, and loading behavior unchanged.
- Match the Apple Notes reference's source-row width, height, selected background, and content padding.

## Evidence

- Same-height crops showed Mudsnote using roughly `24pt` outer source-row margins while the reference visually tracked closer to `14pt` at the Mudsnote capture scale.
- Source symbols were nearly flush with the selected background; Apple Notes leaves a clear internal leading inset.
- Mudsnote source rows accumulated vertical position faster than the reference because `36pt` rows were too compact.

## Implementation

- Expanded source rows to `292x44` inside symmetric `14pt` column insets.
- Increased source text/symbol sizes proportionally and moved the selection radius to `10pt`.
- Added `LibrarySourceButtonCell` to inset native button content by `18pt` without replacing button actions or hit targets.

## Verification

- Five targeted main-layout, count, empty-folder, nested-folder, and folder-lifecycle tests passed.
- Full `swift test` passed: 102 tests in 2 suites.
- `git diff --check` passed.
- `./scripts/package_app.sh` installed the packaged build at `/Applications/Mudsnote.app`.
- Same-height navigation crops confirmed source-row outer margins and symbol-to-selection leading distance now closely match the Apple Notes reference; the custom button cell visibly applies its inset.
- Final comparison: `/tmp/mudsnote-visual-qa-source-list-geometry-20260710/apple-notes-vs-mudsnote.png`.
