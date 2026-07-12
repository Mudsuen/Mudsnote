# 2026-07-12 single sidebar edge

## Request

Remove the visibly overlapping traces around the rounded left sidebar.

## Baseline

- Branch: `main`
- HEAD: `aed643f`
- Existing agent-owned iteration 163 changes were still uncommitted.
- Pre-existing iOS companion changes remain outside this iteration.

## Changes

- Removed the source surface's custom `1pt` CALayer border.
- Preserved native sidebar material, darkening tint, rounded clipping, and split-view separation.
- Added a regression assertion that the surface has no custom border.

## Verification

- Focused sidebar and autosave tests passed.
- Full `swift test` passed.
- `./scripts/package_app.sh` packaged and installed `/Applications/Mudsnote.app`.
- Strict code-sign verification and installed-app launch passed.
- Expanded comparison: `/tmp/mudsnote-expanded-164/apple-notes-vs-mudsnote.png`.
- Visual inspection confirmed one continuous rounded sidebar edge without the former inset outline.

## Decisions

- AppKit owns the structural sidebar edge; the nested source surface only owns material, tint, and clipping.

## Next

- Continue tuning collapsed geometry and toolbar details against state-matched Apple Notes references.
