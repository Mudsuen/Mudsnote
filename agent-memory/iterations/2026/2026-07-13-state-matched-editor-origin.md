# State-matched editor content origin

## Problem

The deterministic collapsed reference and installed Mudsnote fixture selected the same `感悟` note at the same `304x292pt` crop, but the Mudsnote title remained about `25px` higher and `12px` farther left at `2x`. Earlier origin tuning had compounded measurements from different clear crops and overcorrected the current shared editor origin.

## Change

- Increased the editor stack safe-area top inset from `6pt` to `18pt`.
- Increased the shared horizontal editor inset from `22pt` to `28pt`.
- Preserved the `20pt` date row, `4pt` date-to-title spacing, `8pt` title-to-body spacing, title/body typography, and TextKit body padding.
- Updated the layout contract to pin both state-matched origin values.

## Verification

- Focused three-pane layout regression passed.
- Full `swift test` passed.
- `/Applications/Mudsnote.app` was repackaged and passed strict code-signature verification.
- Collapsed title pixels now measure `x=459–546, y=196–238` versus Apple Notes' `x=459–543, y=197–238`: `/tmp/mudsnote-visual-qa-192-collapsed/apple-notes-vs-mudsnote.png`.
- Installed content-state visual QA passed at `/tmp/mudsnote-visual-qa-192-content`.
- Installed create/save/search/trash/restore/move/attachment/relaunch smoke passed at `/tmp/mudsnote-library-smoke-192`.

## Durable rule

Do not carry editor-origin measurements between screenshots with different pane states or selected content. Use the deterministic state-matched fixture and compare exact pixel bounds before changing the shared origin.
