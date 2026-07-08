# 2026-07-08 Editor body rhythm

## Request

Continue the active Mudsnote Apple Notes parity goal, using the new content visual QA state to improve the right-side editor UI while keeping performance lightweight.

## Baseline

- Branch: `main`
- HEAD before work: `1a09114 Add content editor visual QA`
- Dirty files before work: none
- Visual baseline: `/tmp/mudsnote-visual-qa-select-content-fixed/apple-notes-vs-mudsnote.png` now shows `lz合集` selected with visible editor body text. The editor was readable but the body still looked dense compared with the Apple Notes target direction.
- Reference search: existing clipboard images did not provide a clean, unblurred Apple Notes content reference suitable for committing; `docs/visual-qa/apple-notes-reference.png` remains the empty-note reference.

## Changes

- Made `MarkdownEditorTheme` line spacing and paragraph spacing configurable with existing defaults preserved.
- Applied the larger body rhythm only to the Notes-like library editor:
  - line spacing: `3.5`
  - paragraph spacing: `8`
- Kept the standard quick-capture/editor theme defaults unchanged.
- Added regression expectations for the library editor paragraph style.
- Updated the Apple Notes parity roadmap.

## Verification

- Focused tests passed:
  `swift test --filter 'MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|MarkdownRichEditorTests/libraryWindowVisualQASelectionLoadsRequestedContentNote|MarkdownRichEditorTests/richCodecRoundTripsHeadingAndLists|MarkdownRichEditorTests/libraryWindowAutosavesEditedExistingNote'`
- Full tests passed:
  `swift test` (`99` tests in `2` suites).
- Whitespace check passed:
  `git diff --check`
- Packaged app successfully:
  `./scripts/package_app.sh`
  - app path: `/Applications/Mudsnote.app`
- Content visual QA passed:
  `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=content ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-editor-body-rhythm-final`
  - comparison: `/tmp/mudsnote-visual-qa-editor-body-rhythm-final/apple-notes-vs-mudsnote.png`
  - metadata: `/tmp/mudsnote-visual-qa-editor-body-rhythm-final/visual-qa-metadata.txt`
  - selected note: `/tmp/mudsnote-visual-qa-editor-body-rhythm-final/visual-qa-library/Notes/lz合集.md`

## Decisions

- Do not commit the blurred Apple Notes content screenshot as a formal reference.
- Keep this as a visual-only typography change; no note loading, indexing, persistence, or serialization behavior is changed.
- The current toolbar already keeps the earlier lighter direction: the editor tools group uses a compact `192x34` capsule with `0` border width, `0` border alpha, and `20pt` symbols. Do not re-enlarge or reintroduce a visible white rim while continuing Notes parity.

## Next

- Continue side-by-side tuning from the content visual QA output. The next likely targets are source/list density and editor horizontal positioning rather than toolbar enlargement.
