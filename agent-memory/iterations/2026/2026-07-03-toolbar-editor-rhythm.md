# 2026-07-03 - Notes-like Toolbar and Editor Rhythm

## Context

After the library window and list typography passes, visual QA still showed the toolbar search field and editor top spacing as compressed compared with Apple Notes. The remaining mismatch was less about data behavior and more about first-read visual rhythm.

## Change

- Centralized toolbar search size and editor spacing metrics in `LibraryNotesLayout`.
- Widened and slightly tallened the toolbar search field and raised its text size.
- Increased the editor top inset, date row height, date-to-title spacing, title-to-body spacing, and horizontal editor inset.
- Kept this iteration macOS-only; iOS real-device validation is excluded from the current goal.

## Verification

- `swift test --filter 'libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|libraryToolbarUsesNotesLikeDisabledStates|libraryWindowEditorToolbarInsertsRichMarkdownTools'` passed.
- `swift test` passed: 82 tests.
- `git diff --check` passed.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged-app smoke passed: `open -n /Applications/Mudsnote.app --args --library` produced one on-screen `Mudsnote 笔记` window at 1420x860.
- `./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-toolbar-editor` passed and wrote `/tmp/mudsnote-visual-qa-toolbar-editor/apple-notes-vs-mudsnote.png`.

## Remaining Visual Delta

- Toolbar balance is closer, but the side-by-side still shows broader Notes differences around source hierarchy polish and richer export/share behavior.
