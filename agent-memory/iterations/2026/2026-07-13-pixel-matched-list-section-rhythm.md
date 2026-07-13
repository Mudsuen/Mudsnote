# Pixel-matched list section rhythm

## Problem

The scaled side-by-side montage made the iteration 191 card/text correction look aligned, but direct inspection of the original `608x584px` backing images showed the opposite: Mudsnote's selected card began `5pt` too far left, ended too early, extended `2pt` too high, and later group headings sat about `13pt` too high inside otherwise correct row geometry. Metadata lines were also packed more tightly than Apple Notes.

## Change

- Restored the selected-card leading inset to `15pt` and set trailing to `22pt`.
- Restored the note text and separator starts to `40/42pt`.
- Split the selection vertical inset into `6pt` top and `4pt` bottom values.
- Kept the first group title at a `15pt` bottom inset and moved following group titles to `2pt` through a reusable dynamic constraint.
- Increased metadata row spacing from `1pt` to `2.5pt` and balanced content with `4.5/7.5pt` top/bottom insets.
- Preserved the proven `45pt` group and `76pt` note row heights.

## Verification

- Focused three-pane layout regression passed.
- Full `swift test` passed.
- `/Applications/Mudsnote.app` was repackaged and passed strict code-signature verification.
- Original `2x` selected-card bounds are identical at `30,214–355,349px`; later group labels both begin at `y=418px`: `/tmp/mudsnote-visual-qa-193-collapsed-final/apple-notes-vs-mudsnote.png`.
- Installed create/save/search/trash/restore/move/attachment/relaunch smoke passed at `/tmp/mudsnote-library-smoke-193`.

## Durable rule

Use original backing pixels for geometry measurements. Treat first-group placement, following-group placement, card bounds, and metadata rhythm as separate contracts instead of changing shared row heights to compensate for local offsets.
