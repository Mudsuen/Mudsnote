# 2026-07-08 empty new note editor

## Request

Continue the active Apple Notes parity goal for Mudsnote, focusing on UI alignment first while keeping the implementation lightweight and performant.

## Baseline

- Branch: `main`
- HEAD before work: `c551602 Align Notes list leading rhythm`
- Dirty files before work: none
- Visual baseline: `/tmp/mudsnote-visual-qa-note-list-leading-rhythm-final/apple-notes-vs-mudsnote.png` still showed the selected empty-looking `New Note` as a large editor title, unlike the Apple Notes reference where the editor body is blank under the date.

## Changes

- Changed `NoteStore.loadNote` so truly empty Markdown files load with an empty editor title and empty body instead of falling back to the filename as title.
- Kept note-list and search identity stable by using the filename as the display/index title when the loaded title is empty.
- Bumped the lightweight search-index disk cache schema so old cached empty-file titles are rebuilt once.
- Updated the visual QA fixture so `New Note.md` is a real empty Markdown file, matching the Apple Notes empty-new-note comparison state.
- Documented the empty-file editor/list distinction in the Apple Notes parity roadmap.

## Verification

- Commands run:
  - `swift test --filter 'MudsnoteCoreTests/emptyMarkdownFileKeepsEditorTitleEmptyButListsByFilename|MudsnoteCoreTests/searchIndexPersistsAndReloadsAcrossStoreInstances|MudsnoteCoreTests/corruptSearchIndexDiskCacheIsIgnoredAndRebuilt|MarkdownRichEditorTests/libraryWindowShowsEmptyMarkdownFileAsBlankEditorNewNote|MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|MarkdownRichEditorTests/appControllerVisualQAModeUsesIsolatedNoteStore'`
  - `swift test --filter 'MudsnoteCoreTests/emptyMarkdownFileKeepsEditorTitleEmptyButListsByFilename|MarkdownRichEditorTests/libraryWindowShowsEmptyMarkdownFileAsBlankEditorNewNote|MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote'`
  - `swift test`
  - `git diff --check`
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-empty-new-note-editor-final`
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-empty-new-note-editor-verified`
- App/package actually opened:
  - `/Applications/Mudsnote.app` via the visual QA harness.
- Result:
  - Focused core/search/library tests passed.
  - Full `swift test` passed with 97 tests.
  - `git diff --check` passed.
  - Packaged app refreshed at `/Applications/Mudsnote.app`.
  - Final visual QA captured `/tmp/mudsnote-visual-qa-empty-new-note-editor-verified/apple-notes-vs-mudsnote.png`.
  - The empty `New Note.md` list item still displays `New Note`, while the editor no longer shows an invented `New Note` or `无标题` heading.
- Not verified:
  - iOS real-device validation remains intentionally out of scope for the current macOS Notes-parity goal.

## Decisions

- Preserve local file identity in lists/search, but let the editor reflect actual Markdown contents. Empty files should not invent a visible heading.
- Prefer a cache schema bump over runtime compatibility branching so the performance path stays simple after one rebuild.

## Next

- Continue with editor date/title spacing and source/sidebar hierarchy after the empty-new-note state is visually verified.
