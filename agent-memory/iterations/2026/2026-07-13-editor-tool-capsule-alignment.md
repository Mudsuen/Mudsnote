# 2026-07-13 editor tool capsule alignment

## Request

Continue native Apple Notes toolbar parity while keeping Mudsnote lightweight and performance-neutral.

## Baseline

- Branch: `main`
- HEAD: `7ce0d89`
- Dirty files before work: three concurrent iOS companion files, left untouched

## Changes

- Added a transparent `162pt` editor-tools toolbar slot and trailing-aligned the unchanged `155x32pt` glass capsule.
- Added an editor-only `14pt` SF Symbol configuration for checklist, table, link, and attachment commands.
- Replaced the grouped bitmap `Aa` image with a native `13pt` regular text button.
- Disabled the editor-tools item-level border, removing the shifted duplicate outline while preserving `NSGlassEffectView` material and native hover-only button borders.

## Verification

- Focused toolbar structure, disabled-state, and editor-command tests passed.
- Packaged visual comparison: `/tmp/mudsnote-visual-qa-201-editor-tools-final/apple-notes-vs-mudsnote.png`.
- The final toolbar crop shows the capsule beginning at the same normalized x-position as the reference and only one visible outline.
- Full `swift test` passed.
- `/Applications/Mudsnote.app` was packaged and `scripts/library_smoke.sh` passed.
- `codesign --verify --deep --strict /Applications/Mudsnote.app` passed.

## Decisions

- Position native surfaces with transparent layout slots rather than changing accepted visual dimensions.
- Use component-specific symbol configurations; do not change the shared expanded-toolbar symbol size to fix compact editor controls.
- Keep Link in the five-command group because it is a functional local Markdown workflow and part of the previously approved compact toolbar state.

## Next

- Continue with complex editor-content parity or remaining source/list state polish based on a same-state reference audit.
