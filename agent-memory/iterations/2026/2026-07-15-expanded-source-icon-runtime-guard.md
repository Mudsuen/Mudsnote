# 2026-07-15 expanded source icon runtime guard

## Request

Recheck macOS toolbar iconography after the user supplied an expanded-sidebar screenshot where Add Folder and Sidebar Toggle appeared visibly oversized.

## Evidence

- The supplied screenshot renders the two glyphs near the generic toolbar-symbol scale.
- The checked-in Apple Notes reference measures about `44x31px` for Add Folder and `38x30px` for Sidebar Toggle at `2x`.
- The verified source already uses the dedicated `13pt` source-action configuration; a same-system AppKit probe shows `10pt` would undershoot the reference.

## Changes

- Kept the calibrated `13pt` source-action configuration and independent `12pt` collapsed glass configuration.
- Added final-control regressions requiring the expanded AppKit button images to be `20x15pt` and `18x14pt`.
- Rebuilt and installed `/Applications/Mudsnote.app` from the current verified source.

## Verification

- Focused library layout regression passed.
- Full macOS suite passed: `159` tests.
- Production packaging completed and replaced `/Applications/Mudsnote.app`.
- Strict signature verification reached the installed arm64 bundle but the local signing chain returned `CSSMERR_TP_NOT_TRUSTED`.
- Live accessibility smoke could not see the editor tree from the current desktop space, matching the visual-capture frontmost limitation; no product failure was inferred from that environment-only result.

## Decision

Test the image installed on the runtime button, not only the point-size constant. Do not shrink the source symbols below the reference merely to compensate for a stale packaged artifact.
