# Reference-aligned note-card width

## Problem

Equal-scale empty and collapsed visual QA showed that note cards had enough physical width, but their text stack retained intrinsic width when no thumbnail was visible. `Thursday`, preview text, and `Notes` therefore truncated early. The selected card also began about `5pt` too far right and ended too close to the scrollbar compared with Apple Notes.

## Change

- Set the outer note-row stack to fill distribution.
- Lowered horizontal hugging for the text stack so it receives available width before labels truncate.
- Moved the selected-card leading inset from `15pt` to `10pt`.
- Increased the selected-card trailing inset from `21pt` to `31pt` to match the reference scrollbar breathing room.
- Moved note text and row separators `5pt` left.
- Accounted for AppKit's `2pt` stack trailing adjustment while preserving a real `10pt` text gap inside the selected surface.
- Added a real-layout regression that requires the title field to consume nearly all safe width and keeps its drawing rect inside the selection boundary.

## Verification

- Focused three-pane layout regression passed.
- Full `swift test` passed.
- `/Applications/Mudsnote.app` was repackaged and passed strict code-signature verification.
- Installed empty and collapsed equal-scale QA passed; final comparison: `/tmp/mudsnote-visual-qa-191-collapsed-final/apple-notes-vs-mudsnote.png`.
- Installed create/save/search/trash/restore/move/attachment/relaunch smoke passed at `/tmp/mudsnote-library-smoke-191`.

## Durable rule

Validate note-row text with rendered layout width, not only static insets. Selected-card geometry, text origin, and scrollbar clearance are separate measurements and must remain separately testable.
