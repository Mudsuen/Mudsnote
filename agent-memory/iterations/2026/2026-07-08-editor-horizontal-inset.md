# 2026-07-08 Editor horizontal inset

## Request

Continue the active Mudsnote Apple Notes parity goal, aligning UI first while keeping the app lightweight and performant.

## Baseline

- Branch: `main`
- HEAD before work: `ee9d4bf Brighten Notes source rows`
- Dirty files before work: none
- Visual baseline: `/tmp/mudsnote-visual-qa-source-row-weight-final/apple-notes-vs-mudsnote.png`
- The source list was closer to Apple Notes after the row-weight pass. The next visible gap was the right editor content sitting slightly too far inside the editor pane compared with the Notes reference direction.

## Changes

- Reduced `LibraryNotesLayout.editorHorizontalInset` from `52` to `44`.
- Kept the date row, title field, and body container tied to the same inset constant so editor width constraints stay consistent.
- Added/updated regression coverage for the new inset constant.
- Updated the Apple Notes parity roadmap.

## Verification

- Focused tests passed:
  `swift test --filter 'MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|MarkdownRichEditorTests/libraryWindowVisualQASelectionLoadsRequestedContentNote|MarkdownRichEditorTests/libraryWindowAutosavesEditedExistingNote|MarkdownRichEditorTests/libraryWindowEditorToolbarInsertsRichMarkdownTools'`
- Full tests passed:
  `swift test` (`100` tests in `2` suites).
- Whitespace check passed:
  `git diff --check`
- Packaged app successfully:
  `./scripts/package_app.sh`
  - app path: `/Applications/Mudsnote.app`
- Content visual QA passed:
  `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=content ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-editor-horizontal-inset-final`
  - comparison: `/tmp/mudsnote-visual-qa-editor-horizontal-inset-final/apple-notes-vs-mudsnote.png`
  - metadata: `/tmp/mudsnote-visual-qa-editor-horizontal-inset-final/visual-qa-metadata.txt`
  - selected note: `/tmp/mudsnote-visual-qa-editor-horizontal-inset-final/visual-qa-library/Notes/lz合集.md`
  - visual inspection confirmed the editor content starts closer to the pane divider while source/list and toolbar geometry remain unchanged.

## Decisions

- Keep this as a constant-level visual correction. It changes no note loading, editor serialization, indexing, or persistence behavior.
- Do not alter the toolbar or source/list column widths in this pass.

## Next

- Continue with note-list sample-state parity and deeper toolbar icon-state tuning from the final QA output.
