# 2026-05-11 list prefix deletion reset

## Request

- Fix the list display bug where deleting a checkbox marker should make the line stop behaving like a checklist item.

## Baseline

- Branch: `main`
- HEAD: `0e00d6f`
- Dirty files before work: none

## Changes

- `MarkdownRichTextCodec.paragraphKind(at:in:)` now validates that stored list kinds still have a complete visible prefix.
- `EditorWindowController.userDidEdit()` normalizes the current line back to a paragraph when a list prefix is damaged or deleted.
- The checklist/bullet attachment path also removes the leftover one-character spacer when the marker is deleted.

## Verification

- Added `deletingChecklistPrefixResetsLineToParagraph()`.
- Ran `swift test`.
- Ran `./scripts/package_app.sh`.
- Launched `/Applications/Mudsnote.app --args --floating-note` for a packaged-app smoke.

## Decisions

- The visible list marker is the source of truth for whether an edited line still belongs to a list.
- If the marker is damaged or deleted, stale `.qmParagraphKind` attributes are not trusted.

## Next

- If ordered-list marker deletion has a visible edge case, apply the same paragraph-reset behavior to any remaining partial marker text.
