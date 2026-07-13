# State-matched compact typography

## Problem

Collapsed visual QA reused the requested normal fixture while comparing it with an Apple Notes screenshot containing a different selected note and date grouping. The compact toolbar title and group labels also remained oversized, highlighted note previews lost their tail-truncation paragraph style, and the editor title needed a small independent upward adjustment.

## Change

- Added a deterministic `collapsed-reference` seed with the selected `感悟` note and matching previous-Thursday date groups.
- Tightened the collapsed note-list title offset to `-11pt`, title font to `13pt`, and group font to `15pt`.
- Applied `.byTruncatingTail` paragraph style to highlighted list strings.
- Reduced editor date-to-title spacing from `8pt` to `4pt` without changing the date row origin.

## Verification

- Focused library layout and empty-note tests passed.
- Full `swift test` passed.
- Installed `/Applications/Mudsnote.app` passed strict code-signature verification.
- Installed library create/save/search/trash/restore/move/attachment/relaunch smoke passed at `/tmp/mudsnote-library-smoke-187-third` after two transient Accessibility/menu-tracking retries.
- Expanded comparison: `/tmp/mudsnote-editor-title-187-after/apple-notes-vs-mudsnote.png`.
- Collapsed state-matched comparison: `/tmp/mudsnote-collapsed-title-187-after/apple-notes-vs-mudsnote.png`.

## Durable rule

Do not compare compact shell typography against a reference with a different selected note or grouping. Move only the semantic spacing that owns the visible mismatch; do not shift the shared editor origin when the date is already aligned.
